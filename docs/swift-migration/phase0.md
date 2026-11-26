# Phase 0: tooling to build before porting

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Several of these tools now exist. The section for each names it, and the
tool's `--help` or header comment is its manual. A tool a section does not
name does not exist yet. Which items are done is recorded in the checklist in
[orchestration.md §9](orchestration.md). Each item is a `tool` commit and each is
validated on a real file before any unit depends on it.

Its end is an owner checkpoint; on 2026-11-21 the owner let the pilot start
with some items unfinished ([plan.md §1](plan.md)). Within it, tools are built in the order their dependencies
require: the inventory script (section 1) and the runtime snapshot (section 9) come
first, because most other tools and every dossier use them. Phase 0 also
includes the first sanitizer triage (section 4), the warning survey ([warnings.md](warnings.md)),
the stored-state corpus ([stored-state.md](stored-state.md)), the thread sanitizer baseline
([concurrency.md §10](concurrency.md)), the nil-lock assertions in the existing Objective-C
([concurrency.md §2](concurrency.md)), and the test speed work ([test-speed.md](test-speed.md)). Items that the pilot
must validate ([plan.md §2](plan.md)) are still built here; the pilot confirms they work
on real units and refines them.

## 1. Inventory script

Prints, for every implementation file: lines, target (ARC or not), number of
explicit retain/release sites, header fan-in, subclass relationships in both
directions, categories, hazard flags (dynamic dispatch, `NSCoding`, xib class,
AppleScript class, `@synchronized`, `@try`, `+load`), and migration state
derived from the tree and from commit trailers. This is how any agent answers
"what is done and what is next" without trusting a stored list.

For each Objective-C++ file it also reports which of the four classes in
[objcxx.md](objcxx.md) the file falls into, and it reports the progress measures listed
in [README.md §2](README.md).

It is `tools/swift_migration/inventory.py`, with the subcommands `summary`,
`files`, `file`, `history` and `leaf`. It has no `state` or `verify`
subcommand: the ivar and static table is the code database query
`codedb.py classstate`, and the comparison of the inventory's parsed
classes with the database and the runtime snapshot is
`codedb.py verifyinventory` (section 10, "Class state" and "Inventory
verify"). Results it marks heuristic come from text matching, as its
`--help` describes.

## 2. Entry-point census

Given a class name or selector, lists every reference the compiler cannot see.
[hidden-callers.md](hidden-callers.md) explains each source and why it matters.

It is `tools/swift_migration/entry_points.py`, with the subcommands
`method`, `class` (with `--unreached`), `file` and `all-classes` (below).
By the decision of 2026-11-19 ([decisions.md](decisions.md)), everything
the compiler sees comes
from queries on the code database (section 10), and text and XML search
remain only for what the compiler does not see: xibs, storyboards, the sdef,
plists, Core Data models, and names built at run time. The tool searches:

- The selector as a literal: `@selector(...)`, `#selector(...)`,
  `Selector("...")`.
- The selector as a string literal anywhere in Objective-C, Swift, property
  lists, JSON, and scripts, including strings in arrays and dictionaries that
  are later passed to `NSSelectorFromString`.
- **Fragments.** For a selector `fooBar:baz:` it also searches for each
  component and for every prefix and suffix of the first component down to a
  minimum length, to catch selectors assembled by concatenation or `##` token
  pasting and tests such as `hasPrefix:@"contextMenuAction"`.
- The reflective-site registry ([hidden-callers.md §2](hidden-callers.md)): for every site that converts
  between strings and selectors or enumerates methods, whether the queried
  selector or class falls in the set that site can reach.
- Class names: `NSClassFromString`, `NSStringFromClass` results that are
  stored or compared, class-name strings, and `Info.plist` entries.
- xib and storyboard files, parsed as XML: `customClass`, `customModule`,
  actions with their resolved target (a specific object, File's Owner, or
  First Responder), outlets with their owner, bindings, and user-defined
  runtime attributes ([hidden-callers.md §4](hidden-callers.md)).
- `iTerm2.sdef` class, key and method bindings.
- Key-value coding keys and key paths, including those inside `NSPredicate`
  format strings and `NSSortDescriptor` keys.
- `NSCoding` class names in archives and keys in stored dictionaries.
- The Python API and `proto/api.proto` where a name is reflected.

A selector is not renamed and does not lose `@objc` unless the census output
for it is empty and the runtime snapshot (section 9) agrees. A method is
deleted as dead only when the census lists it under "no caller found" on a
current database with every source consulted, in its own commit outside any
port, with the full suite passing afterwards; a method under any other
heading, the weak one included, is not dead ([decisions.md](decisions.md),
2026-11-20).

The census lists a method under "no caller found" only when every source was
consulted and found nothing, and only with at least one runtime method list
(`--runtime-methods FILE`, one per macOS release, written by
`tools/swift_migration/sdk_selectors.py --runtime-methods` on that release or
converted from dumped runtime headers with `--runtime-methods-from-headers`).
Without a list every candidate is "not decided", whatever its name and its
superclass, and the run is incomplete; a leading underscore is evidence of
nothing in either direction ([decisions.md](decisions.md), 2026-11-20). With
the lists, a candidate is "possibly called by the system" when its first
framework superclass or an ancestor of it implements the selector with the
same class-or-instance kind, or when it is a method of a category on a
framework class that the class itself, an ancestor or a framework subclass
implements. Otherwise, when any framework class implements a method with the
selector, it is listed under a separate weak heading, because the frameworks
send many selectors to objects of unrelated classes after
`respondsToSelector:`. Only a selector that no framework class implements in
any list stays under "no caller found". The run names every release
consulted and the kind of list each had, and a commit that deletes code on
its strength quotes them. A list converted from dumped headers cannot show
methods that other images add to a class through categories (the dumps have
none, not even public ones such as `-[NSString sizeWithAttributes:]`), so a
release checked only with such a list is checked less thoroughly than one
with a live list.

The app also links frameworks that are checked into the repository as built
bundles (`ThirdParty/Sparkle.framework`, `CoreParse.framework`,
`NMSSH.framework`, the Swift `Highlightr.framework` and
`SwiftyMarkdown.framework`, and the bundles of `ColorPicker/`,
`BetterFontPicker/` and `SearchableComboListView/`). Their code is in
neither the database nor the runtime method lists, but it sends the
methods of its delegate protocols (Sparkle's `SPUUpdaterDelegate`,
CoreParse's `CPTokenRecogniser`). A method whose selector any header of
such a bundle declares is never "no caller found", whatever its class or
language: it is listed as possibly called by the system, in a subgroup
naming the framework. The selectors come from the code database's
declarations for the headers units read, and from the headers read as text
for the rest; a selector match is enough (found 2026-11-21: 9 live methods
had been listed as uncalled).

**Whole tree.** `entry_points.py all-classes --out DIR` runs the census of
every class with a method or Swift member defined outside `submodules/`,
the test directories and the migration's tools, in one process, deciding
each class exactly as `class CLASS --unreached` does (tested on the fixture,
and on 20 real classes, all identical). It writes `methods.tsv` (every
method with its heading, scope, definition, counts per source, flags and
reasons), the methods under "no caller found" split into
`no_caller_in_scope.tsv` and `no_caller_out_of_scope.tsv` (by the
definition's directory, README.md section 2), and `summary.json` and
`summary.txt` (counts per heading, all and in scope). Methods in generated
files are listed with the heading `generated` and left out of the others,
as the class mode leaves them out. It reads the class-keyed tables through
indexed temporary copies (the database file is not written), searches the
resources once and reads each runtime method list once; progress goes to
stderr, and `--memory-limit MB` (default 1500) stops it with status 2.

Run of 2026-11-21 on the database recaptured that evening (every unit and
module current), with the six runtime method lists of the earlier run:
2,525 classes, 44,627 methods, 91 seconds, peak resident size 586 MB (a
scratch driver had taken about an hour). In the migration's scope: 38,274
called, 569 possibly called by the system, 128 weak, 70 through a Swift
protocol requirement, 73 in code not compiled, 10 Swift USRs, 2 not
decided, 149 called only from tests, 2 defined elsewhere, and 743 with no
caller found; 52 more with no caller found are in `ThirdParty/` outside the
scope, and 2,102 are in generated files. A sample of 40 of the 743 (seed
20261122, `random.Random(seed).sample` over the list sorted by class and
method) was checked by hand: `git grep` over every tracked file outside
`submodules/` for the selector's first keyword, the property name for
accessors (assignments for setters), the Swift spelling, and the custom
getter's property; protocol conformance (including the prebuilt
frameworks), target-action, xibs, key-value coding, overrides, menu
validation and the sdef. All 40 are uncalled; no mechanism was missed.
With 0 misses in 40, the 95% upper bound on the share of the 743 that a
missed mechanism reaches is about 7.5% (rule of three), about 56 methods;
the earlier 57-row sample, taken before the prebuilt-framework fix on a
database of the same day, also found none of another kind. Several are not
removable on their own although uncalled: advanced-setting getters and
setters that a `DEFINE_*` macro generates with the setting, one half of a
property, a method a protocol requires.

The census can be defeated by a sufficiently indirect construction, such as a
name built from pieces at run time, and it sees only the build configuration
the code database was captured from. It is one of two defenses. The other, the runtime snapshot, does
not depend on finding callers at all.

## 3. Binding tests

Written once, they protect every later port. They parse files and ask the
Objective-C runtime; they do not need to instantiate anything.

- For every app xib: each `customClass` resolves with `NSClassFromString`.
- Each outlet's owner class has a settable property or ivar of that name.
- Each action whose target is a specific object or File's Owner is implemented
  by that object's class (`instancesRespondToSelector:`).
- Each First Responder action is implemented by at least one class in the app
  or in AppKit, and the set of app classes implementing it equals a recorded
  list (so a port that drops or adds an implementer fails the test).
- Each binding key path and each user-defined runtime attribute key resolves on
  its target class.
- For every class, key and method binding in `iTerm2.sdef`, it resolves.
- For every `NSCoding` class name found in the stored-state corpus
  ([stored-state.md](stored-state.md)), `NSClassFromString` finds it.

A second, best-effort test instantiates each nib with its real owner where
that has no side effects, and fails on the "Unknown class in Interface Builder
file" and "not key value coding-compliant" messages. Nibs that cannot be
loaded safely in a test are listed with the reason.

## 4. Sanitizer configuration

A build configuration (or scheme arguments, whichever proves simpler) for the
test target that compiles the Objective-C with:

- `-fsanitize=nullability` (runtime check of nullability claims; [nullability.md §7](nullability.md)).
- `-fsanitize=signed-integer-overflow,implicit-conversion,float-cast-overflow,integer-divide-by-zero,shift,bounds`
  for the discovery runs in [translation-rules.md §1](translation-rules.md).
- No recovery for the nullability group in tests, so a violated claim fails the
  test instead of scrolling past in a log.

A second mode for Development builds reports without aborting, so that
day-to-day use of a debug build surfaces violations that tests do not reach.

These exist as scripts, each documented by its `--help`:

- `tools/swift_migration/sanitizer_tests.sh MODE [TEST ...]` builds and runs
  the tests in its own build directory, with MODE `nullability`, `integer`
  or `thread`. In `nullability` mode a targeted run (test names given)
  writes the first violation that is not suppressed to a file and ends the
  test host, so the test fails. It does this with `halt_on_error=1` on a
  recoverable build, because the app violates a claim while launching, and
  with `abort_on_error=0`, so the host exits without a crash report. A
  whole-suite run, or one with `--recover`, does not end the host: every
  report goes to a file and the run fails on any of them, listing the tests
  they came from, except those in the nullability baseline
  (`docs/swift-migration/nullability-baseline.tsv`, the known, not yet
  triaged violations, compared after the run; nullability.md section 7).
  The runtime suppressions file,
  `tools/swift_migration/sanitizer_nullability_suppressions.txt`, stays
  empty; `--collect` turns off the abort and the suppressions and fails on
  nothing, for triage and for writing the baseline. `integer` and `thread` run in recover mode and write every report
  to a file. `--parallel` runs two test workers unless `--workers N`;
  `--skip ModernTests/Class[/test]` (repeatable) leaves a class or test out
  (`-skip-testing:`); `--jobs N` limits the build tasks that run at once
  (`-jobs N`).
- `tools/swift_migration/sanitizer_app.sh` builds the Development app with
  the nullability and integer groups in recover mode: the second mode above.
  `--jobs N` limits its build tasks.
- `tools/swift_migration/sanitizer_summary.py` groups and counts the reports
  of a run by kind and location, with those in scope listed apart.

The first run under this configuration will report violations in the 464
headers that are already annotated. Those claims were never checked and Swift
already depends on them. Triage of that first batch is Phase 0 work: each
report is a wrong annotation (change it to `nullable` and fix the Swift
callers) or a real bug (log it).

## 5. Swift interface snapshot

A script that prints the interface Swift sees for one Objective-C header.
`swift-synthesize-interface` in the current toolchain does this when given a
module map for the header. It is the tool that makes header changes reviewable:
the diff of the snapshot before and after an `annotate` commit shows exactly
which members changed from `T!` to `T?` or `T`, and nothing else may change.

Example of its output for a header with one unresolved method:

```swift
open class Foo : NSObject {
    open var name: String
    open func claimedNonnull(_ x: Int32) -> String
    open func unspec(_ a: String!, block b: ((String?) -> Void)!) -> String!
    open func take(_ s: String)
}
```

## 6. Lints for migration Swift

Applied to files created by `port` commits (tracked by a marker comment or by
the trailer history, to be decided in the pilot). The lints are
`tools/swift_migration/swift_lints.py`. It uses the trailer history: a Swift
file is a migration file when a commit with a `Swift-Port:` trailer of
`kind=port` added it, with rules for renames, code carried into new files,
and ported lines in existing files that its `--help` states in full. It
lints Swift text token by token, so it cannot check the items below that
need types; every run lists those under "Not checked by this tool", each
with the reason. They fail the gate on:

- An integer initializer applied to a non-literal (`Int(x)`, `Int32(x)`,
  `UInt(x)` and so on), whether the argument is an integer or a
  floating-point value. Use `numericCast`, `init(truncatingIfNeeded:)`,
  `init(bitPattern:)`, `init(exactly:)`, or the helpers in [translation-rules.md §1](translation-rules.md).
  Floating-point initializers (`Double(x)`, `CGFloat(x)`, `Float(x)`) cannot
  trap and are allowed.
- A plain `+`, `-`, `*`, unary `-` or `<<` on a fixed-width integer type
  without either an arithmetic helper or a `// bounded-by-type: <reason>`
  comment ([translation-rules.md §1](translation-rules.md)). If this proves impractical as a lint it becomes a
  review checklist item.
- Unsafe pointer APIs without a marker comment on the line above
  ([translation-rules.md §8](translation-rules.md)): `UnsafePointer`, `UnsafeMutablePointer`,
  `UnsafeRawPointer`, `UnsafeMutableRawPointer`, `UnsafeBufferPointer` and its
  variants, `withUnsafe...` calls, `assumingMemoryBound`, `bindMemory`,
  `unsafeBitCast`, `Unmanaged`, and `OpaquePointer`. The marker on a call
  that passes `&x` to a pointer parameter is to be enforced by type-aware
  lints on the Swift AST, which knows whether `&x` becomes a pointer or an
  `inout`; until that unit is done it is a review item (owner queue Q20
  item 6).
- `!` force unwrap, `as!`, `try!`, `unowned`, `unowned(unsafe)`. An
  implicitly unwrapped type in a declaration (`var x: T!`) is not a force
  unwrap: [translation-rules.md §7](translation-rules.md) allows it on a
  property, listed in the commit message, and
  [hidden-callers.md §4](hidden-callers.md) forbids it on an outlet, which
  the lint reports.
- An implicitly unwrapped type outside a property (a parameter or result
  type, a local or file-scope variable, `init!`) without a
  `// SWIFT-MIGRATION-IUO: <reason>` marker on the line above or at the end
  of the same line ([translation-rules.md §7](translation-rules.md);
  decisions.md, 2026-11-20). A `!` nested in a type (a function type, an
  array, tuple or generic argument) or after `as` or `is` is reported too;
  Swift rejects those. `swift_lints.py --list-iuo` lists every marked site
  with its reason, and the markers that cover none.
- A `var` declared at file scope, stored or computed, whatever its
  modifiers and attributes, including one inside a `#if` block and one in
  the top-level code of `main.swift` (decisions.md, 2026-11-20;
  [translation-rules.md §5](translation-rules.md)). A static or global
  variable from Objective-C becomes a static property of a type. There is
  no marker for it. A file-scope `var` with an implicitly unwrapped type
  gets this finding and the one above. A file-scope `let` is not reported
  until the owner confirms whether it is banned too.
- Use of an implicitly unwrapped value from Objective-C without binding it
  first. This lint is what drives the on-demand annotation in [nullability.md](nullability.md).
- `fatalError`, `assert`, `precondition`, `assertionFailure`,
  `preconditionFailure` (use the `it_` versions: `it_fatalError` for
  `preconditionFailure`, and `it_assert(false, ...)` or a beta assertion for
  `assertionFailure`, which does nothing in release builds while the
  Objective-C `assert` it replaces stays enabled there; decisions.md,
  2026-11-20).
- `async`, `await`, `Task`, `actor`, and new `@MainActor` or
  `MainActor.assumeIsolated` in a stage-one file ([concurrency.md §8](concurrency.md)).
- An `objc_sync_enter` that is not followed by a `defer` with the matching
  `objc_sync_exit` on the same constant ([concurrency.md §2](concurrency.md)).
  The lint requires `defer { objc_sync_exit(x) }` on the next line.
- An optional, implicitly unwrapped, or force-unwrapped argument to
  `objc_sync_enter` ([concurrency.md §2](concurrency.md)).
- `os_unfair_lock` or `pthread_mutex_t` as a Swift stored property
  ([concurrency.md §5](concurrency.md)).
- `URL`, `Date`, `Data`, `IndexSet`, `Calendar`, `Locale` appearing in a
  stage-one file where the Objective-C used the `NS` class ([translation-rules.md §4](translation-rules.md)).
- `NSNumber as? Int` and similar bridging casts ([translation-rules.md §4](translation-rules.md)).
- `==` between `String` values that came from `NSString` where the Objective-C
  used `isEqualToString:` or `isEqual:` on data that can contain non-ASCII
  ([translation-rules.md §4](translation-rules.md)). This one may need to be a review checklist item instead of a
  lint.

**Where they run.** Once per session, among the closing checks
([lifecycle.md §5](lifecycle.md)), over the session's port commits: the
type-aware lints (`swift_ast_lints.py`), `warning_survey.py` and
`swift_interface.py` need a compile-command capture, which a lane does not
have, so the orchestrator runs, in its own checkout,
`capture_compile_commands.sh` (a clean build, so a heavy job; `--jobs N`
limits its build tasks), then `codedb.py update` (with
`--accept-removals` when a port deleted files), then the three tools and
`swift_lints.py REV` on each port commit. A finding goes back to the
author, and its fix is a new commit of the unit. In a lane the author may
run `swift_lints.py --staged` early, as a check of its own; it counts every
Swift file staged with a `kind=port` message as part of the port, so a
test file staged in the same lane draws findings that are not the port's.
The dossier's length is not a lint of this kind: `dossier_cap.py` runs in
the gate of every commit that changes a dossier ([README.md §5](README.md)).

## 7. Helper library

A small Swift file of named operations so that ported code says what the C did.
It is `sources/Infrastructure/SwiftMigrationHelpers.swift`; the comment at
its top says how each build type behaves:

- Arithmetic and narrowing helpers for fixed-width integers: `it_add`,
  `it_subtract`, `it_multiply`, `it_negate`, `it_shiftLeft`, and
  `it_narrow(_:to:)`. Each returns the C result (add, subtract, multiply and
  negate wrap, narrowing keeps the low bits, a left shift drops the bits
  shifted out) and, with `BETA`, fails a beta assertion on overflow, a
  changed value or an undefined shift count, so such an event crashes in
  Development, beta and nightly builds and gives the C result in release
  ([translation-rules.md §1](translation-rules.md)).
- Float-to-integer conversion: `it_floatToInteger(_:to:)` truncates toward
  zero as C does and clamps NaN to 0 and out-of-range values, infinities
  included, to the bounds of the type, the same on both processors; with
  `BETA` it fails a beta assertion on NaN or a value out of range.
  `it_floatToIntegerUnchecked(_:to:)` gives the same result with no check in
  any build, for hot paths with the owner's sign-off.
- `it_synchronized(obj) { }` built on `objc_sync_enter`, for blocks with no
  control flow out of them ([concurrency.md §2](concurrency.md)).
- `it_betaAssert`, the Swift equivalent of `ITBetaAssert`, and
  `it_conservativeBetaAssert`, the equivalent of `ITConservativeBetaAssert`
  ([assertions.md](assertions.md)).

`ObjCTry` already exists in `sources/Infrastructure/ObjCExceptions.swift` for
calling code that raises `NSException`.

## 8. Baselines

- Performance: results of `tools/perf/run_stress_test.sh` and
  `PerformanceTests` for a fixed set of modes on a named machine. The
  harness is `tools/swift_migration/perf_baseline.py`, with
  `perf_compare.py` to compare results; the scenarios, the result file, the
  quiet-machine rule and the commands are in
  [performance.md §3](performance.md). The baseline was taken on
  2026-11-22; its numbers are in [performance.md §3](performance.md).
- Memory: resident size and allocation counts for a scripted workload. The
  same harness: the `memory.scrollback_fill_20k` scenario in process, and
  the app's resident size during each stress run.
- Lifetime: the witness tests and instance census in [lifetimes.md](lifetimes.md).
- Data races: a thread sanitizer configuration for the test suite, which
  avoids its false reports in Metal, and a triaged list of the races the
  existing code already reports ([concurrency.md §10](concurrency.md)).

## 9. Runtime snapshot of a class

A tool that runs inside the test host and prints, for named classes, what the
Objective-C runtime knows about each. It is
`tools/swift_migration/runtime_snapshot.sh`, which runs
`ModernTests/RuntimeSnapshot.swift`; the format is described at the top of
that file. A snapshot starts with a header naming the architecture, the
build configuration, and the sanitizer variant. For each class it records:

- Class name, superclass, and directly adopted protocols.
- The language the class is defined in (`objc`, `swift`, or `unknown` for a
  class made at run time whose name does not say), and the image (binary)
  that defines it.
- Every instance variable, with its name and type encoding. Key-value coding
  falls back to ivars and xib outlets connect to them, so an ivar with no
  property still matters.
- The ownership of each ivar as far as the runtime can tell it, from the
  class's strong and weak ivar layouts and its ARC flag (read through
  `_class_getIvarMemoryManagement`, which also cross-checks the decoding):
  a label and the ivar's words in the layouts, with the layouts and the flag
  on their own lines. Where the runtime cannot tell, the label says what it
  cannot tell apart, never "not owned": an unretained pointer from one
  retained by hand, a C struct from a C++ object, anything in a class
  compiled without ARC, and a Swift class's stored properties, which the
  layouts do not describe. The labels are listed in
  `ModernTests/RuntimeSnapshotIvarOwnership.swift`. A contradiction between
  the layouts, the ivar list and the runtime's own answer is an
  `OWNERSHIP-CONFLICT` line, which fails every comparison.
  `tools/swift_migration/ivar_ownership_check.py <snapshot>` prints the
  compiler's answer for each ivar from the code database beside the
  runtime's, and reports where they disagree.
- Every instance method and class method: selector and type encoding, and
  the image of any method implemented in a different binary from its class,
  including methods that a system framework adds at run time.
- Every declared property with its attributes (type, ownership, atomicity,
  readonly, dynamic, getter and setter names, backing ivar). The ownership
  label is only what the property's own attribute string states, and is
  `unrecorded` when that string does not state it. For a Swift class a weak
  property is labeled `weak-or-unowned`, because the runtime cannot tell
  `weak`, `unowned` and `unowned(unsafe)` apart.
- Which of its selectors are also implemented by a superclass.
- Duplicates, as described below.

What it does not record:

- The ownership of an ivar beyond what the layouts say (see above), and of
  a Swift class's stored properties.
- The declaration order of ivars. They are listed sorted by name, so a
  change in their order is not reported, although that order decides
  teardown order under ARC ([arc.md](arc.md)). The `dealloc` audit has to
  cover it.
- Direct methods and properties (`objc_direct`). They are not registered
  with the runtime, so they never appear in a snapshot. A direct property's
  backing ivar is an ordinary ivar and is listed.
- Selectors and keys that a class answers dynamically (forwarding, method
  resolution, `valueForUndefinedKey:`).
- The class of an object parameter or return value: every method encoding
  writes an object as plain `@`, so `NSString *` becoming `NSArray *`, or
  `id` becoming a class, is not seen. The reviewer compares the Swift
  signatures with the Objective-C declarations; for an Objective-C header
  the Swift interface snapshot (section 5, `swift_interface.py`) shows the
  types Swift sees.
- Nullability: a Swift parameter that is not optional where the
  Objective-C method accepted nil is not seen, and a nil passed from
  Objective-C then traps. Nullability claims are made and proven by the
  annotate process ([nullability.md](nullability.md)) and checked at run
  time by the nullability sanitizer configuration (section 4).
- Which members of a Swift class are `dynamic`.

**Duplicates.** A selector that appears more than once in a class's own
method list is a duplicate, because which implementation runs is not
defined. The exception is `+load`: a class and each of its categories may
have one, and the runtime calls every one of them, so a repeated `+load` is
listed but is not a duplicate. A property, unlike a method, can
legitimately appear more than once in a class's property list: the compiler
emits the `NSObject` protocol's properties once for each category or
extension that adopts a protocol derived from it. Repeated properties are
duplicates only when their attributes differ. A snapshot marks each
duplicate, and a comparison involving it fails if the duplicate is new or
changed between the snapshots (count, encodings or images) or has an entry
in the app's own image (the app, the test bundle, an embedded framework, or
no binary); one identical in both snapshots with every entry in a system
image is listed under “Duplicates present in both snapshots, not from this
app: ignored” and does not fail. The owner, 2026-11-25, asked “may the
comparison ignore a duplicate that is present identically in both
snapshots and isn't in the unit's own code?”, answered “Yes, of course”.

**What a snapshot reflects.** A snapshot records the process as it is when
the snapshot is taken, including methods and classes that system frameworks
add at run time. That is why the script runs the snapshot as the only test
in its run: no other test can change the process first. The tool can only
snapshot the build configuration that the `ModernTests` scheme builds for
testing (today Development, with the address sanitizer variant). It has no
option to choose another, so code that exists only in beta or release builds
is not seen. The before and after snapshots must come from the same
architecture, build configuration and variant; the comparison refuses them
otherwise.

**Comparing.** `tools/swift_migration/compare_runtime_snapshots.sh <before>
<after>` compares two snapshots. Its report has these sections, each only
when it has entries: NO VERDICT (classes it gives no verdict for, with the
reason), ERRORS, DUPLICATES, DIFFERENCES, UNCLASSIFIED DIFFERENCES
(differences in the classes that get no verdict, for a person to check),
allowed differences, and the duplicates ignored as above. A last line says PASS, FAIL, or ERROR, and a pass also
lists what the comparison does not cover. Exit status:

- 0: the snapshots match, apart from the expected differences allow-listed
  in `ModernTests/RuntimeSnapshotComparison.swift`. The allow-list is empty.
  An entry is added only when a real port has shown that the difference
  occurs and is harmless.
- 1: they differ, or some class gets no verdict: one that changed language
  from Swift to Objective-C, or whose language is `unknown` in either
  snapshot.
- 2: they cannot be compared: bad arguments, an unreadable or malformed
  file, snapshots from different architectures, configurations or variants,
  or a failure of the script itself.

**What must match.** The snapshot is taken before and after a `port`
commit.

- **While the class stays in Objective-C** (an incremental port,
  [lifecycle.md §2](lifecycle.md)), **the two must be identical**, apart
  from the allow-list, which the pilot will establish.
- **For a class that changes language** from Objective-C to Swift (a small
  file ported whole, or the flip), the two must be **identical in
  meaning**. Methods with their type encodings, protocols, superclass and
  the decoded property attributes must match exactly. The systematic
  differences that the Swift compiler introduces are classified by the
  comparison tool and listed for the reviewer instead of failing: property
  attributes in a different order, backing ivars named without the
  underscore or absent for a computed property, Swift's storage listed as
  ivars whose types the runtime encodes as unknown, no ivar layouts,
  `.cxx_destruct` added or removed, a getter or setter name Swift does not
  write when the method is still there, a pointer that swiftc encodes
  differently for the same C type (`^v` where clang writes a pointer to an
  incomplete struct, such as `^{_NSZone=}` for `NSZone *` or an opaque
  struct pointer, and the const qualifier `r` on a CF type such as
  `CFString`; any other change of pointee fails), and the `NSObject`
  protocol's and
  `@optional` protocol properties that clang copies into the class's
  property list and Swift does not. Anything the runtime cannot verify is
  listed under CHECK AGAINST THE SOURCE: every Objective-C ivar that
  vanished (code that reaches it by name breaks), weak versus unowned,
  ownership that one side does not record, every initializer of the Swift
  class whether kept or added (the init family, and new-family class
  methods: Swift lists `-init` for every class, and a stub for each
  inherited designated initializer the class does not override, such as
  `-initWithFrame:` for an `NSView` subclass; a stub traps when called and
  the runtime cannot tell it from a real initializer, so the reviewer
  checks that the Swift class declares or inherits each one, or that the
  header marked it `NS_UNAVAILABLE` and the commit message says it now
  traps (traps.md)), one
  check per class that Swift calls members not marked `dynamic` directly,
  past key-value observing and swizzling, and one check per property that
  was atomic and is nonatomic after. Every Swift property is nonatomic; an
  atomic property that is relied upon is ported with its value stored in a
  `MutableAtomicObject` and an `@objc` computed property over its `value`
  ([concurrency.md §3](concurrency.md)), and the runtime cannot see that
  lock, so the reviewer confirms it, or that the dossier shows the
  property was atomic by accident. Snapshotting such a port
  (`RuntimeSnapshotPortAtomicSwiftFixture`, for an object, a struct and a
  scalar property) showed no other difference than those already
  classified: the attribute string gains `N` and loses its `V` code
  (a computed property has no backing ivar), the Objective-C ivar
  vanishes (a check), the `MutableAtomicObject` appears as Swift storage
  with no type encoding, and the accessors' encodings are unchanged. These do not change the exit
  status. Everything else fails, including a dropped `+load` or
  `+initialize`, which Swift cannot implement, a dropped `-dealloc`
  (Swift lists `-dealloc` only for a class that declares `deinit`), an
  added initializer that overrides nothing, a property that lost its
  atomicity and also changed in a way that fails on its own (it became
  readonly, or its type or ownership changed), and nonatomic becoming
  atomic, which a Swift property never is. Between two Objective-C
  snapshots atomic becoming nonatomic still fails. The rules were found by snapshotting an Objective-C class and
  its stage-one Swift port; they are described in
  `ModernTests/RuntimeSnapshotComparison.swift`, and real snapshot pairs
  test them (`tools/swift_migration/tests/test_compare_runtime_snapshots.py`).
  A class that moves from Swift to Objective-C still gets no verdict.

**Open items in the cross-language comparison.** These ports fail the
comparison today, and there is no way yet to record that a failure has
been accepted:

- A class with an Objective-C `-dealloc` whose Swift port has no `deinit`:
  the `-dealloc` line is removed. It fails rather than becoming a check,
  the stricter choice, until there is a way to record that nothing
  `-dealloc` did is still needed.
- A class that implements `+load` or `+initialize`, which a Swift class
  cannot implement.

The snapshots come from arm64 only. On x86_64 swiftc encodes `Bool` as `c`,
as clang encodes `BOOL` there (read with `otool -ov` from an Intel build in
the `iTermCacheableImage` port; the `x86_64` build of [README.md §5](README.md)).

This is the main guarantee for hidden callers. Stage one keeps every selector,
so a caller that reaches the class through a selector string, a xib, the
responder chain, a proxy, key-value coding, or a method-list enumeration keeps
working as long as the runtime sees the same class with the same methods. The
snapshot proves that without needing to find a single caller. It catches:

- A selector that Swift spelled differently from the Objective-C one.
- A method that silently lost `@objc`, or was dropped as apparently unused.
- A method that a macro used to generate and that nobody wrote out in Swift.
- A changed type encoding, which matters to `NSInvocation`,
  `NSMethodSignature`, and `iTermReflection`.
- A property that changed from strong to weak, and one that changed from
  atomic to nonatomic (in a port to Swift, an item to check).
- A delegate or data source method that no longer matches its selector.

Finding callers by search (section 2) is still required whenever a selector
is going to change or disappear, which happens in `undynamic` commits and in
stage two.

## 10. Code database

The facts that callers, overrides and reflective sites need come from the
compiler, written once into a SQLite database and then queried
([decisions.md](decisions.md), 2026-11-19). It is in
`tools/swift_migration/codedb/`; `codedb.py --help` is the manual.

- **Capture.** `capture_compile_commands.sh` runs one clean Development
  build with Clang's `-gen-cdb-fragment-path`, and keeps the build log's
  Swift driver commands and each Swift module's file list. `--jobs N`
  (xcodebuild `-jobs N`) limits the build tasks that run at once.
- **Other projects.** `capture_compile_commands.sh --other-projects`
  captures, under the same lock, the in-repository Xcode projects that the
  main build does not compile, as listed in
  `tools/swift_migration/codedb/other_projects.json`: `ColorPicker/` (the
  framework target), `submodules/CoreParse` (from which the Makefile builds
  the framework the app embeds; outside the scope, captured so that its
  sends to the app's delegates are parsed) and the four command line tools
  of `SignedArchive/`. (A stale copy of the CoreParse sources at
  `ThirdParty/CoreParse` was removed on 2026-11-21.) A
  project whose project file is absent (a submodule not checked out, as in
  a lane) is reported as not captured, which is not an error. Each project
  is built clean in its own directory under `tmp/codedb/other-build/`
  (never the project's own build directory, `Build/` or Xcode's
  DerivedData), one scheme per kept target, in Debug for the native
  architecture, and its fragments and a
  capture record (its own build settings and its spec) are kept in
  `tmp/codedb/other-fragments/`; `codedb.py cdb` merges them, each unit
  under the target `NAME:TARGET`, and `update`, `cdb` and the queries
  report a project whose file list, build settings or spec changed since
  its capture as out of date. Only Clang units are captured: the Swift of
  `BetterFontPicker/` and `SearchableComboListView/` is not, and the app
  reads the frameworks' prebuilt headers, not these sources.
- **Objective-C extraction.** `codedb.py update` runs the extractor
  (`extractor/`, built on upstream LLVM 22 by `extractor/build.sh`) on every
  translation unit that is not current, each under the memory watchdog
  `guard.sh`. Each unit records digests of its command and of every file it
  read, so that a query can say which rows are stale.
- **Swift references.** For each Swift module, `swiftreader/swift_refs`
  streams the Swift compiler's JSON AST dump into tables of references to
  Objective-C declarations and of Swift declarations visible to Objective-C
  (`swiftdb.py`).
- **Preprocessor.** Macro definitions with facts read from their tokens
  and from the AST of their expansions, every expansion of a repository
  macro (counts per file for macros from the SDK), every `#if`-family
  directive with its value in each unit, and the ranges each unit skipped
  (`extract_sends.cpp`, "Macros and conditional compilation").
- **Classes and the SDK.** `objc_class` and `objc_adoption` hold the
  superclass of each Objective-C class in the repository and the protocols
  its declarations list (not those of classes declared in Swift, whose
  superclass the Swift tables do not hold: `classinfo` says so);
  `sdk_method`, `sdk_class` and `sdk_adoption` the Objective-C declarations
  outside the repository (every method and property accessor, with its
  container, framework, `@optional` and `IBAction`), recorded once per
  module and configuration (deployment target, and Objective-C++ or not,
  which can change what a header declares) by the unit that holds the
  claim (`sdk_claim`, `tu_module`). Declarations in a repository header
  that units read only through a Clang module are recorded as a header's
  are.
- **Evidence for code not emitted.** A send, ivar reference or static
  reference that the compiler certainly does not emit at `-O0` because a
  condition folds to a constant is marked (`in_constant_false_branch`, with
  the condition's location): the arm an `if` skips (`if (0)`, a `const`
  local or `static const` with a constant initializer, an enumerator) when
  that arm holds no label, and the operand skipped by `c ? x : y`,
  `0 && x` or `1 || x` when the operator is a scalar value that is not part
  of a branch condition. The rule is deliberately narrower than what the
  compiler drops: an aggregate or complex conditional, or one inside an
  `if` condition, is not marked even where the compiler drops an operand,
  so a mark never excuses code the object holds (`extract_sends.cpp`,
  "Constant conditions").
- **Evidence for unreachable code.** A send in code that no path from its
  function's entry reaches is marked (`send.in_unreachable_code`), from
  Clang's control-flow graph of the innermost function, method, block or
  lambda: after `return`, `break`, `continue`, `goto`, `throw`, `@throw`, or
  a call the code generator treats as noreturn (the `noreturn` attribute,
  `_Noreturn`, `[[noreturn]]`, `__builtin_unreachable`); not after
  `__builtin_assume(0)`, `__builtin_trap`, `__builtin_debugtrap` or an
  `analyzer_noreturn` function, where Clang's graph ends the path but the
  compiler emits what follows. The skipped arm of a folded `if` or conditional
  operator (the constant-condition rule above) is not a path, so the code
  after `ITAssertWithMessage(NO, ...)` and `ITDebugAssert(NO)` is
  unreachable. The default edge of a `switch` that lists every enumerator
  is followed, because the compiler emits it. The mark reflects the unit's
  own configuration (`tu.configuration`, Development for the capture;
  `ITDebugAssert` is `assert` there and a cast to void in Deployment), and
  the queries that list sends (`sends`, the census's callers) show such a
  row with the mark "unreachable code" and that configuration rather than
  hiding it. It is narrower than what the compiler drops: a send in no
  block of the graph, a block or lambda written in unreachable code, the
  code after `while (1)` without a `break` and template patterns are not
  marked (`extract_sends.cpp`, "Unreachable code"). That a marked send is
  never emitted is checked against an object file for each form of the
  fixtures (`UnreachableCodeTest`), not proven for every form. Schema
  version 13.
- **What Swift imports.** For each captured Swift module whose command
  has a bridging header (only `iTerm2SharedARC`; `ModernTests` has none of
  its own and sees it through that module), `update` (and
  `update --imports-only`) fills the `swift_import` tables from the
  compiler's symbol graph (`swift_interface.py`'s import pipeline: the
  module's emit-module job with `-emit-symbol-graph`, streamed): every
  Objective-C or C declaration Swift can see through the bridging header,
  by USR, with its Swift name, declaration and availability. For the app it
  takes about 25 to 40 seconds, the compiler peaking at about 2.3 GB, and
  writes about 22,000 rows; the rows are stale when the command, the
  compiler, the tool or any header or module interface the module's
  dependency information names changed (not its Swift files). The query
  `swiftimports` joins them to the database's declarations by USR (the USR
  forms are the same; a macro's is computed from its location) and gives,
  for each declaration that is absent, the reason a rule finds, each
  checked with `swiftc` probes: an unread header, a range the module's
  configuration skips, an accessor of a property, a container not
  imported, `NS_UNAVAILABLE`, `UNAVAILABLE_ATTRIBUTE`,
  `NS_SWIFT_UNAVAILABLE` or a variadic list in the declaration's own text,
  a type naming a class Swift cannot see, type facts, the kind of a macro,
  or "probably usable through" a member whose Swift name it collides with.
  Otherwise it says "absent from the symbol graph: reason unknown; it may
  still be usable from Swift": the database does not record the types of
  parameters. Headers of a framework's Clang module are not judged: Swift
  imports them as that module. C functions, enums, typedefs and records
  have no table in the database, so they are found only by name (their
  Objective-C name or Swift base name); a name nothing declares is said to
  be so.
- **Queries.** `sends`, `methods`, `selrefs`, `reflective`, `reach` and
  `swiftrefs`, each taking a selector (`reflective` takes options instead),
  `ivars`, `ivarrefs`, `statics` and `staticrefs` for state, `macros`,
  `macrouses` and `skipped` for the preprocessor, `sdkmethods` (who in
  the SDK declares a selector), `classinfo` (a class's superclass chain
  into the SDK and its protocols, direct and inherited) and `swiftimports`
  (what Swift imports, above), with `--update` to bring
  the database up to date first. `macrolint` is the lint of
  [hidden-callers.md §6](hidden-callers.md), over the checked-in
  `macro-classification.tsv`. Every query exits
  0 when it answered with rows, 1 when it answered with none, 3 when the
  answer may be incomplete (a unit or module that is not current, a compile
  database that does not cover the project, or no rows while a text search
  finds a match in a file that is not parsed), and 2 on error.

- **Class state.** `codedb.py classstate CLASS` is the ivar and static
  table of [objc-state.md](objc-state.md) (`classstate.py` documents every
  field). One row per ivar (declared in the `@interface`, a class
  extension or the `@implementation`, or synthesized for a property) with
  its type as the compiler prints it, where it is declared, ownership under
  the ARC mode of the class's `@implementation`, whether Swift can import
  the type and why not, the methods named like it, and every function that
  uses it with the kind of use; one row per static the class's files
  define, with whether it is written after its initialization (a non-const
  C++ object is "not decided", because the extractor records its operator
  and member calls as reads; a once token says so); and the statics and
  globals those files use but do not define. Importability is decided from
  the type facts the extractor records and, for the repository classes and
  protocols a type names anywhere in it (found by name among the words of
  the type the compiler prints), from the import table of the bridging
  header (`swiftimports`). At the top level, one Swift does not import
  makes the verdict "no", as `PTYTab._variablesScope` shows. Inside the
  type the verdict depends on the position, as swiftc showed with a
  forward-declared class (`classstate.py`, above `position_verdict`): in a
  block's parameters or result, a type argument of `NSArray`,
  `NSDictionary`, `NSSet`, `NSCache`, `NSMapTable`, `NSHashTable` or a
  repository generic, or a C array's element, "no"; a type argument of
  `NSMutableArray` and the other SDK classes whose API notes drop their
  arguments, "degraded"; a pointer to an object pointer or a function
  pointer, "degraded" (OpaquePointer). Any other position, or a type
  nested more than one level, is "unknown" with "visibility: not checked
  for the parts of this type". Records, typedefs and enums inside a type
  are not judged.
  `--snapshot FILE` compares each ivar's ownership with a format 3 runtime
  snapshot (section 9), with the rules of `ivar_ownership_check.py`.
  `--all` writes the table of every class with an `@implementation` in the
  migration's scope (less generated protobuf and Core Data classes), one
  class at a time, then a summary; `--json` makes it JSON Lines. On the
  whole tree (2026-11-21: 1,230 classes, 7,789 ivars of which 463 are not
  importable and 47 unknown, 26 of those the ColorPicker framework's) it took 6 to 11 minutes on the shared machine
  and peaked at about 100 MB, writing 25 MB of text. Each class's header
  says that the per-class text searches were not made.
  Limits: no text search is made for a row (the database answers all of
  them); `--all` skips the per-class searches of unparsed files and
  skipped ranges that `classstate CLASS` makes, so a class whose answer
  must be complete is asked alone. The visibility of typedefs, enums and C
  records is not checked (no table of them), nor associated objects that
  categories add, locks other than `@synchronized`, key-value observing of
  accessor names, and how often a reference runs. Static functions are not
  listed and methods are not grouped by shared state.

- **Inventory verify.** `codedb.py verifyinventory [CLASS...]` compares
  what `inventory.py`'s parser finds in each file (classes, superclasses,
  protocols, ivars, methods, properties) with the database, class by
  class, and with `--snapshot FILE` (format 2 or 3) a runtime snapshot's
  superclasses, ivars and methods with the database. Each difference is
  explained by a printed rule or is UNEXPLAINED (`verify_inventory.py`
  lists the rules). On the whole tree (2026-11-21: 1,325 classes, 1,918
  files, 33 seconds, 70 MB) 2,274 differences, 2,268 explained (macros,
  files no unit reads, inactive `#if` branches) and 6 not: four methods of
  `iTermWindowImpl.m`, which `PTYWindow.m` includes four times with
  different settings (a known limit), and the two tool bugs in `bugs.md`.
  The snapshot side reads format 3; on 2026-11-21 the only format 3
  snapshots were of the two pilot classes, taken before their ports, so
  against the current database they show the ported classes' ivars as
  runtime only. Their ownership was checked with `ivar_ownership_check.py`
  against a database from before the ports: every ivar agrees or is
  answered by the compiler.

- **Cross-check.** `codedb.py crosscheck` compares each Objective-C unit
  with its object file (`crosscheck.py`): the selectors it sends, the
  methods and ivars it defines, and the number of call sites of each
  selector against the unit's send sites; every difference is explained by
  a printed rule or reported as UNEXPLAINED. A selector only in the
  database is explained by the constant-condition marks only when every row
  of it is marked; the counts always leave the marked rows out, so a marked
  row can neither explain a call site nor cancel one. A larger count in the
  object from an always_inline function is explained only up to the copies
  of that function that its references in the unit allow (`function_ref`).
  The rule `unreachable-code` explains a selector only in the database
  when every row of it is marked as unreachable code (or as in a constant-
  false branch, or is in a function the object does not define) and at
  least one is unreachable; the counts leave the unreachable rows out like
  the constant-false ones, and a count that agrees only once they are left
  out is listed as explained by that rule, so each such site is printed.
  The rule holds for the configuration the database was extracted in
  (Development).
  `--build-root` reads the objects of another build of the same sources,
  such as a sanitizer build. A C++ function, and a C function of an
  Objective-C++ unit, is found in the object by its mangled name, read
  whole: the identifiers of the function's name, each a whole
  `<length><identifier>`, and whether it is a constructor or destructor
  must be the database's, except that the symbol may have more
  identifiers before or between the database's (inline namespaces, which
  the database's name leaves out). So a name inside a longer one (`6Helper`
  in `16HelperXxxxxxxxxx`) no longer matches; a member `Foo::Helper` still
  matches a database name `Helper`, because the extra leading identifier
  may be an inline namespace (the safe direction). The constructor of a
  class template (`ns::Tm<int>::Tm`) is recognized. A symbol whose form the
  reader does not know (an ABI tag, an operator) is matched by its
  identifiers in order, as before. On the database of 2026-11-21 this
  changed no unit's result.
  Known difference it reports as UNEXPLAINED, by design, in the safe
  direction (sends in the database that the object lacks): a condition
  with a side effect that the compiler folds at one site and not at an
  identical one, which nothing in the AST predicts
  (`iTermWebSocketFrame.m`, `-closeFrameCode`, the assignment used as a
  condition in bugs.md: three call-site counts, `UTF8String`,
  `callStackSymbols` and `stringWithFormat:`). It goes when that bug is
  fixed.
  Whole tree at schema 13 on 2026-11-21: 1,121 Objective-C units, 1,119
  compared (the two others were test files edited after the capture), and
  those three counts the only UNEXPLAINED differences, so
  `codedb.py crosscheck` exits 1 until that bug is fixed.
  Limits not fixed: the rules for boxed numbers, strings and values, array
  and dictionary literals and fast enumeration explain any excess of their
  framework selectors in a unit without checking that the unit has such a
  literal, so a missed explicit call of one of those selectors would be
  explained away. The rule `direct-method` explains an object with fewer
  call sites of a selector whenever the unit defines or references a
  method symbol for it, objc_direct or not (two counts it explained in
  `PTYSession.m` and `PseudoTerminal.m` were unreachable sends); that is
  the safe direction.

- **Reflective registry.** `tools/swift_migration/reflective_registry.py`
  checks `reflective-sites.md` against the database: every dynamic
  reflective call has a section 3 bullet (matched by file, function, call
  and argument, not line), no bullet is stale, the bullet lines and the
  summary table agree with the database, and the names table is the union
  of the `Names:` lines. `update` rewrites the bullet lines and the summary
  table and refuses while a site needs reading. Outside its bullets the
  registry cites places by file and function, not by line (1,330 prose
  references and 57 bare line numbers were rewritten that way on
  2026-11-21), so nothing there moves with the code; `check` does not
  read the prose. The 47 bullets of sections 4 to 9 that cite lines keep
  `FILE:LINE`, the form `entry_points.py` parses; their 130 line numbers
  (with the lists and "also" locations) were brought to the tree of that
  day and are not regenerated (36 of the bullets also name their
  function).
  `check` is the lint of [hidden-callers.md §2](hidden-callers.md): a new
  use of a reflective API with a name that is not a literal is a new
  dynamic row and fails it (`LintFixtureTest` in
  `tests/test_reflective_registry.py`: `NSSelectorFromString`,
  `performSelector:`, `valueForKey:`, `NSClassFromString`, and
  `NSInvocation` through `methodSignatureForSelector:` and `setSelector:`;
  the same calls with literal names do not). It sees only the calls of the
  extractor's table (`extractor/reflective_table.h`, listed by `codedb.py
  reflective --list`) in Objective-C. It does not see the conversions of
  a selector or class to a string (`NSStringFromSelector`,
  `NSStringFromClass`, `sel_getName` on non-literals), `_cmd` used as
  data, names assembled by `##` or string formatting until they reach a
  call of the table, `conformsToProtocol:`, the forwarding methods,
  Swift's `Selector("...")` and other reflective Swift, and the methods
  Cocoa finds by naming convention (key-value coding accessors,
  validation, scripting accessors); those stay with the reading of
  [hidden-callers.md §3](hidden-callers.md). Bullets are paired with rows
  in line order, so when one of two sites with the same key disappears,
  the wrong one of the two bullets may be the one reported stale.

Limits: function bodies in a repository header that units read only
through a Clang module are not walked, so their sends and references are
not recorded. None exists today (33 repository headers are read that way,
none with a function body); the extractor counts the bodies it skips
(`tu.module_bodies_skipped`) and `update` warns when the count is not zero.

Not built yet: the Swift of the other projects (`BetterFontPicker/`,
`SearchableComboListView/`).

## 11. Extraction analysis

`tools/swift_migration/extraction/extract_check.py` checks the block of an
`extract` commit ([large-code.md §2.2](large-code.md)) from Clang's AST;
its `--help` is the manual. The facts come from `extraction_facts`, a
LibTooling program built on upstream LLVM 22 by `extraction/build.sh` (the
same LLVM as the code database's extractor). It is run directly on one file
with that file's compile command from the code database's compile database
(or a command given on its command line), not through the database: nothing
is stored.

- **`range PATH:FIRST-LAST`**, before the extraction. Reports, in thirteen
  categories:
  - every statement that can leave the block (`return`, `break`,
    `continue`, `goto`, throws and rethrows, calls to `noreturn`
    functions), with its target and whether that target is inside the
    block, including exits hidden in a macro's body;
  - control flow entering the block (a `goto` from outside, a `case` label
    of an outer `switch`);
  - the scopes around and inside the block, and those an exit leaves;
  - every local variable and parameter declared outside the block and used
    in it, classified as read, written, both, address taken or bound to a
    reference, captured by a block or lambda (by copy or by reference),
    with its type and ownership qualifier, and whether it must come back
    (see "Liveness" below); writes through a reference variable and
    through a pointer are reported as such;
  - variables declared in the block and used after it;
  - `self`, `_cmd`, `super`, ivars and `this`; an assignment to `self` must
    come back;
  - globals, file-scope statics and static data members, which are
    unaffected while the helper stays in the same file and must be made
    visible if it moves to Swift or another file;
  - values that change when code moves (`__func__`, `__FUNCTION__`,
    `__PRETTY_FUNCTION__`, `__LINE__`, also inside macros such as `DLog`),
    as notes;
  - macro expansions, with the definition in effect;
  - other hazards: variable-length arrays, `alloca`, `va_list`, `setjmp`,
    `__attribute__((cleanup))`, destructors and precise lifetimes that
    would end earlier, static locals, copy constructors, lifetime-extended
    temporaries, and the address of a variable or compound literal
    declared at the top level of the block being taken (it dangles if it
    is stored somewhere used after the block).

  Each category ends in "none found", a list, or "unknown" with the
  reason: a range that does not align with whole statements, clang errors,
  code in or after the block that this configuration does not compile (the
  configuration is named), a computed `goto`, a structured binding, or a
  use the tool cannot classify.
- **`after`**, given the commit (or the two versions as files) and the same
  `--extract` declaration as `pure_move.py`. It runs pure_move's check (on
  git objects through `pure_move.check_extract`, or on the two files with
  pure_move's own comparison functions), checks that the helper's
  parameters and the call cover the variables that must go in and come
  back, flags an out-parameter of object type whose ownership differs from
  the variable it replaces (including the implicit `__autoreleasing`), and
  pairs every exit of the block with what the caller does after the call.
  Each pairing is "matches a known safe pattern" or "needs review". The
  known safe patterns: a returned flag tested by an `if` whose branch is
  the same exit; a `void` call in tail position, or `return helper(...)`
  for a block that was the function's tail and is exactly the helper's
  body, returning the same value at each exit; a case or loop body whose
  exits became returns and whose call is followed by the same `break` or
  `continue`; values passed by value, pointer or reference under the same
  names; a variable coming back as the helper's return value (`x =
  helper(...)`) only when the block assigns it on every path before
  reading it (its first use is an unconditional top-level assignment and
  no exit comes before it), since the return value replaces the value it
  had before the block, and no caller form that would keep that value is
  accepted; `self` assigned in the block coming back as `self =
  [self helper]` from a helper that ends with `return self;`. The call
  statement must sit where the block was: with pure_move's pairing of the
  unchanged lines, the nearest code lines around it must be the ones that
  came right before and after the block. Every
  statement of the helper outside the moved lines must be a form one of
  these patterns needs (the final `return self;`, the flag pattern's final
  constant, a final `return x;` with a declaration of `x` before the moved
  lines when `x` comes back as the return value); every line declared with
  `--allow-added` must be in the helper or the call statement (or be the
  `break` the break-after-call pattern needs), and every line declared with
  `--allow-removed` must be blank or a comment. The report lists the
  declared lines. Clang errors in the after version make the result
  unknown. The result is clean (exit 0) only when every pairing matches and
  pure_move confirms that the block's lines moved unchanged; an extraction
  that rewrites lines (`z` becomes `*z`) always needs review. What it
  cannot prove: that the declared lines (signature, call, new returns)
  mean what the patterns assume beyond the facts it checks,
  that arguments are evaluated as often and in the same order as before,
  and anything about other build configurations. A clean result is not a
  proof; the reviewer still reads the diff.
- **`compiled`**: compiles both versions at `-O2` with the file's compile
  command and compares the enclosing function's LLVM IR after a stated
  normalization (or every function in the file, when the enclosing
  function is inlined into its callers). The normalization's rule for
  globals and functions is written out in the tool's `NORMALIZATION` text:
  string literals, lookup tables, CFString literals, the runtime's class,
  selector and protocol reference slots and global block literals are
  compared by content; other constants by name and content; globals the
  code can write by name; private and internal functions (block invoke
  functions, lambdas, static functions) by the digest of their own
  normalized bodies. "identical" means that, in this configuration, the
  enclosing function's optimized code with the helper inlined is the same
  instruction for instruction as before, up to that normalization: it does
  not cover other configurations, code the helper does not inline, or two
  static functions whose bodies are equal but whose addresses the program
  compares. "different" is not proof of a bug, and a difference only in
  function-name strings (`__func__` and the like) is reported as one the
  extraction makes by design. "not comparable" means the helper is not
  inlined. On the fixtures,
  correct extractions compare identical and broken ones (a dropped
  write-back, a `return` or `break` that only leaves the helper, a
  `__autoreleasing` out-parameter, a different static) compare different.
  On real code it has so far given only "different" (a correct extraction
  from `iTermSelect`, where the optimizer laid out the loop differently)
  or "not comparable" (an Objective-C method, which is never inlined, and
  a helper of a very large function, which the inliner declined), so a
  difference has to be read.

Liveness is lexical. A variable written in the block is listed as coming
back when it is named later in the function, anywhere in an enclosing loop,
after a backward `goto`, or in a block of a `__block` variable; when it is
a reference (the write goes to its referent); and when its address was
taken before the block. The list can therefore hold a variable that does
not need to come back. It can miss one that is read later only through an
alias it does not see: a pointer to it taken inside the block and stored
(that is listed among captures and addresses, not as coming back), or a
reference held by another object.

Other limits: facts hold for one compile command, so code that another
configuration compiles is not seen (it is reported as unknown only where
this configuration skips it); exceptions thrown by calls, the ownership of
objects returned under manual reference counting, and the order and number
of argument evaluations are left to review. A block that contains or
straddles an `@available` or `__builtin_available` check is not analyzed
for it: a helper that lacks the guard is caught by the compiler's
`-Wunguarded-availability`. A helper declared `noexcept` or `nothrow` is
flagged only for an explicit `throw` in the block; an exception thrown by a
call inside such a helper terminates the program, which the tool does not
report. `compiled` reports "different" for a block literal moved into the
helper even when the block is identical, because the stack block's
lifetime markers move with it. A static that no code reads is optimized
away, so a change to it is not seen.

How far to rely on each mode, as the third review of this tool concluded:
`range` is reliable for exits, variables that must come back, and writes
to `self` and ivars in ordinary Objective-C. For `compiled`, "identical"
is strong evidence within the limits above, but Objective-C methods are
never inlined, so on real code it usually says "not comparable". For
`after`, its "needs review" findings are trustworthy; a clean result means
that every pattern it knows was satisfied, and a reviewer still reads the
declared lines. The `after` report prints the last sentence in its header.

In a git worktree the file is
parsed at the path the compile command names, with the worktree's
contents, so headers come from the checkout the compile database was
captured in; a file whose case differs from the compile database's entry
is matched case-insensitively and the report says so. Tests:
`python3 -B -m unittest discover -s tools/swift_migration/extraction/tests
-p 'test_*.py'`.

## 12. Qualifying checks: trivial, light or full

`tools/swift_migration/qualify_unit.py UNIT` prints the path a unit takes
([lifecycle.md §3](lifecycle.md)), the trivial conditions T1 to T8 and the
light conditions, each PASS, FAIL or MANUAL with its evidence and the query
or search that produced it; `--json` gives the same as data; its `--help`
is the manual. UNIT is a class or `Class(Category)`. The exit status
answers the light conditions as before (0 when nothing FAILs); for a
category unit, 0 when it is trivial. The trivial conditions that need the
code (body lines brace to brace, what ARC would change, C pointers and
arrays) come from Clang's AST of each implementation file, parsed with its
compile command by upstream clang 22 (`unit_ast.py`, one to five seconds a
file); the rest from the code database and the light conditions. A MANUAL
is never trivial. `--classify` gives the path of every unit under
`sources/` (class units, and category units whose file belongs to no class
unit) and lists the trivial ones by body lines.

The light conditions: users, instance-variable accesses, overrides, properties,
reflective calls, sends, macro expansions and static references come from
the code database; xibs, storyboards, the sdef, property lists, Core Data
models and the registry from the entry-point census's parsers (section 2),
and the census's own per-method counts decide "nothing but ordinary
sends". Text search is used where the database records nothing: a mention
of the class that is no send or reference (a type, a cast), counted as a
user and labelled; and in the unit's own files, calls of C functions such
as `dispatch_async`, `objc_setAssociatedObject` and `NSStringFromClass`,
and `@synchronized`. Profile keys are the string macros of any header that
defines at least 20 of them (today `ITAddressBookMgr.h`), found through
the database's macro expansions. A condition is MANUAL, never PASS, when
the database cannot decide it: a unit of the class's files that is not
current, a stale app file that mentions its selectors or properties, a
census hit on a selector another class also
has, a key-value coding key sent to an object of unknown class, a send to a
repository method that itself stores (one level), a use from per-frame or
per-token code (the hot directories and `PTYTextView*`, directly or through
one class of a user file), a timer. Any access to its instance variables
from outside the unit FAILs. The callers' thread is MANUAL until the
orchestrator records the answer with `--callers-thread TEXT`, which is
printed as RECORDED with the text as evidence. Every condition that can
FAIL has a fixture that FAILs it alone, the trivial conditions too. `--list` checks every class with an
implementation under `sources/` in one process (about 2.5 minutes, 300 MB)
and prints those that no condition FAILs, by size, with the conditions
still MANUAL for each. It needs the repository and a current code database,
nothing else.
