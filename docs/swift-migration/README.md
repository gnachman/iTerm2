# Objective-C to Swift migration

These files define how iTerm2's Objective-C and C code is moved to Swift. They
are the source of truth for every agent and person doing migration work.

**Every agent reads this file in full before any migration work**, then reads
the topic files its task needs, as listed in section 1, before starting the
task.

A unit takes one of three paths ([lifecycle.md §3](lifecycle.md)), which
`qualify_unit.py` prints: the trivial path for very small code (no
dossier, one commit holding tests and port, one review), the light path (a
short dossier, a `test` and a `port` commit, one review), or the full path
of [lifecycle.md §1](lifecycle.md). Light and full units pass the whole
suite before their code commits; the sanitizer suites, the `x86_64`
build, the lints and one more whole suite run once per session, over
everything that landed ([lifecycle.md §5](lifecycle.md)). The owner allowed further units after
the two pilot units on 2026-11-22.

If a rule turns out to be wrong, the rule is changed here first, with the
owner's agreement, and the reason is recorded in `decisions.md`. Factual
errors and out-of-date descriptions in these files may be corrected without
asking the owner; a change to a rule still needs the owner and a
`decisions.md` entry.

The work will take months and many thousands of commits, carried out by many
agents with no shared memory. The process is designed around that: every step
is small, mechanical where possible, checked by a tool where possible, and
leaves the app working.

A reference of the form `[nullability.md §5](nullability.md)` points at a
numbered section of another file. A plain "section 5" means a section of the
file it appears in.

## 1. Where to find things

| File | What it covers | Read it when |
|---|---|---|
| [workflow.md](workflow.md) | How work runs unattended: the author and reviewer loop, parking, the owner queue, the nightly schedule and usage budget, and the morning review | Before orchestrating anything; before acting as an author or a reviewer |
| [orchestration.md](orchestration.md) | The orchestrator's runbook: what to do from a cold start with no memory, how to choose work, how to brief the author and the reviewer, how to commit and stop, and the Phase 0 checklist | The orchestrator, at the start of every session |
| [lifecycle.md](lifecycle.md) | The eight steps of the full path, the dossier and its length, runtime verification, crash reports, porting a large file a few methods at a time, the trivial and light paths, and the closing checks run once per session | Before any unit. The orchestrator knows it thoroughly |
| [translation-rules.md](translation-rules.md) | How each Objective-C construct is written in Swift: integers, nil, things that trap, Foundation types, control flow, the shape of a stage-one class, unsafe pointers | Every `port` commit and every review of one |
| [assertions.md](assertions.md) | Which assertion to use, what to assert, what not to | Every `port` commit |
| [nullability.md](nullability.md) | How header annotations are made and proven, and other claims a header makes to Swift | An `annotate` commit, or a port that touches unannotated API |
| [arc.md](arc.md) | Moving a file from manual reference counting to ARC | An `arc` commit |
| [objc-state.md](objc-state.md) | What Objective-C state Swift can and cannot see, the remedies, the per-ivar decision, and the `ivar_` naming scheme | Any incremental port, and any port that needs state from a class still in Objective-C |
| [hidden-callers.md](hidden-callers.md) | Selectors built at runtime, the runtime API, macros, and xib files | Building a dossier; any `undynamic` commit; any unit with xib ties, macros, or reflective code |
| [concurrency.md](concurrency.md) | Locks, atomics, queues, closure capture, actor isolation, the existing thread model, and detection | Any unit that takes a lock, dispatches a block, or is used from more than one thread |
| [stored-state.md](stored-state.md) | Reading and writing data saved by other versions | Any unit that encodes or decodes anything |
| [lifetimes.md](lifetimes.md) | Ownership, cycles, and objects dying sooner or later than before | An `arc` commit, and any unit with delegates, stored blocks, timers or observers |
| [interop.md](interop.md) | What each language can see of the other, and the ordering constraints that follow | Choosing what to port next; any unit with subclasses, categories, or shared enums and structs |
| [large-code.md](large-code.md) | Emptying the giant classes, and functions too large to test or port as they are | Any work on `PTYSession`, `PseudoTerminal`, `PTYTab`, `PTYTextView`, or a function over about 150 lines |
| [objcxx.md](objcxx.md) | Objective-C++ files and headers that include C++ | A unit with a `.mm` file or a header that includes C++ |
| [performance.md](performance.md) | Rules that keep ported code fast, measurement, and the hot paths that are deferred | Any unit the dossier marks as warm or hot |
| [phase0.md](phase0.md) | The tools the process depends on | Building or using any of them |
| [warnings.md](warnings.md) | The warning survey, the strict set, and turning warnings on one file at a time | An `explicit` commit; Phase 0 |
| [test-speed.md](test-speed.md) | Where test time goes, the fast tier, and the rules about slow tests | Phase 0; adding tests; changing what the gate runs |
| [stage-two.md](stage-two.md) | Improvements that become possible once no Objective-C uses a type | An `improve` commit |
| [plan.md](plan.md) | The order of work, and what the pilot must validate | Choosing what to do next |
| [baseline.md](baseline.md) | Measurements of the codebase taken when the process was written | Background |
| `decisions.md` | The dated record of decisions and their reasons | Before proposing to change a rule |
| [owner-queue.md](owner-queue.md) | Items that need the owner's attention | The orchestrator, at the start of each night; the owner, each morning |

## 2. Goals and scope

Goals, in the owner's words:

1. Reduce unsafe code (out-of-bounds reads and writes, use-after-free, etc.).
2. Enable refactoring of classes that have grown too large to change safely.
3. Eliminate manual reference counting.
4. Preserve performance. Some C and Objective-C may stay in hot paths.
5. Improve test coverage as a side effect of porting.
6. Fix bugs.
7. Make it possible to widen 32-bit integers (line numbers, pixel offsets) to
   appropriate types, and 32-bit floats to doubles where appropriate.

In scope: the owner's own Objective-C, C and C++ that is compiled into the
app or its helper programs, wherever it lives in the repository. Most of it
is under `sources/`. The rest is in `SignedArchive/`, `pidinfo/`,
`iTerm2SandboxedWorker/`, `ShellLauncher/`, `ColorPicker/`,
`SearchableComboListView/` and `BetterFontPicker/`. The owner confirmed all
of them on 2026-11-19.

Out of scope:

- Everything under `submodules/`.
- Generated code (`sources/proto/*.pbobjc.*`, Core Data generated files).
- Third-party code under `ThirdParty/`, with the exception below.
- Hot paths, until everything else is done ([performance.md §2](performance.md)).

In scope although it lives under `ThirdParty/`:

- `ThirdParty/PSMTabBarControl`. It is now predominantly the owner's code. It
  has 18 Objective-C implementation files (about 14,500 lines, of which
  `PSMTabBarControl.m` is 5,700 and `PSMTabDragAssistant.m` is 3,700), one
  Swift file, and about 96 explicit retain/release sites in 4 files. It is
  migrated by the same process as `sources/`. Its drag and drop logic is
  covered by deterministic tests that drive the drag calculations directly,
  not by manual testing; characterization tests for those units follow that
  pattern.

Other directories under `ThirdParty/` come into scope only if the owner says
so, and are then added to this list.

**Measuring progress.** The measure is the number of lines of Objective-C, C
and C++ remaining in scope, from the inventory script. The goal is zero. That
is almost certainly not reachable: some code is expected to remain (hot paths
that stay in C, atomics, structs that must keep a C layout). Each such piece
is listed with its reason in `hot-paths.md` or `decisions.md` and is then not
counted as unfinished.

Intermediate measures, also from the inventory script and never stored:

- Files compiled without ARC. This reaches zero first.
- `null_unspecified` annotations remaining.
- Files that import `iTermStrictWarnings.h`.
- Counts of `SWIFT-MIGRATION-SHIM`, `SWIFT-MIGRATION-UNSAFE`,
  `SWIFT-MIGRATION-FROZEN-REFERENCE`, `SWIFT-MIGRATION-IUO`, and `ivar_`
  uses.

**Final checklist.** The migration is finished when all of these hold:

- No Objective-C, C or C++ remains in scope except the pieces listed with
  reasons as above.
- A search of the whole repository for `SWIFT-MIGRATION-FROZEN-REFERENCE`
  returns nothing ([large-code.md §2.3](large-code.md)).
- A search for `SWIFT-MIGRATION-SHIM` returns nothing ([objc-state.md §1](objc-state.md)).
- A search for `ivar_` accessors returns nothing ([objc-state.md §2](objc-state.md)).
- Every remaining `SWIFT-MIGRATION-UNSAFE(hot)` marker names the measurement
  that justifies it ([translation-rules.md §8](translation-rules.md)).
- No file is compiled without ARC.
- `claims.md` and `units/` are empty, and `bugs.md` holds only entries the
  owner has chosen to leave.

## 3. Decisions already made

Made by the owner on 2026-11-18. Do not relitigate these. `decisions.md` holds
the dated record with reasons; this section states the rules that follow.

**Process**

- AI-written documents are allowed in `docs/swift-migration/` as an exception
  to the rule in `CLAUDE.md`. Nowhere else.
- Migration commits go directly onto master with linear history, not through
  pull requests (section 5).
- The work runs mostly unattended. Each change is made by an Opus subagent
  and reviewed by another, always a fresh one, until a review finds nothing
  meaningful. The agents start at midnight, stop at a usage budget tied to
  the day of the week, commit locally, and never push; the owner reviews and
  pushes in the morning ([workflow.md](workflow.md)).
- What needs the owner, and what does not, is in section 7.
- The pilot started on 2026-11-21 with some Phase 0 items unfinished; they
  continue alongside it ([plan.md §1](plan.md)). No unit after the two
  pilot units starts without the owner's word ([lifecycle.md §3](lifecycle.md)).
- A unit gets a dossier in proportion to its code: none on the trivial
  path, a short one on the light path, and on the full path one within a
  cap tied to its size ([lifecycle.md §3 and §4](lifecycle.md); the owner,
  2026-11-24).
- Bugs found while building tools or porting are recorded in `bugs.md` and
  not fixed, unless one blocks a port (changed 2026-11-21).
- Large files are ported a few methods at a time, not in one commit
  ([lifecycle.md §2](lifecycle.md)).
- Hot paths are left until last. They need individual attention and must not
  block the bulk of the work ([performance.md §2](performance.md)).
- A port does not wait in nightly builds before its dependents are ported
  (changed 2026-11-19). Crash reports and beta assertion failures are acted
  on when they arrive and attributed to ports by line
  ([lifecycle.md §1](lifecycle.md), step 7).
- Rollbacks should be rare and are handled case by case.
- The measurable goal is zero Objective-C, accepting that it is almost
  certainly not reachable (section 2).

**Correctness**

- An out-of-bounds array access is a bug that at least sometimes crashes in
  Objective-C. It may crash in Swift too. Do not add code to tolerate it.
- In release builds ported arithmetic and conversions do what the C they
  replace does in practice: add, subtract, multiply and negate wrap,
  narrowing keeps the low bits, a left shift drops the bits shifted out and
  masks its count as the hardware does. A float converted to an integer is
  the exception, because C has no fixed result for it: it clamps to the
  type's range and NaN gives 0. In Development, beta and nightly builds
  and in tests each such event is a beta assertion, so that it is found
  ([translation-rules.md §1](translation-rules.md); changed 2026-11-20,
  replacing the rule that overflow clamps in release).
- The helper calls that do this are scaffolding. Each is replaced with
  ordinary Swift in stage two, and the inventory counts the calls that
  remain. Code whose C relies on wrapping (a hash, a checksum, bit packing)
  uses Swift's wrapping operators instead, with a comment.
- Messaging nil and getting zero is very often the intended behavior
  (`int count = [myArray count];`). Port it as such and do not assert on it. Assert
  on real assumptions: a value in a range, an object belonging to a
  collection, a state ([assertions.md](assertions.md)).
- Assertions are added liberally, through a Swift equivalent of
  `ITBetaAssert`. They must not cost performance or add crashes in release
  builds ([assertions.md](assertions.md)).
- A nil lock passed to `@synchronized` locks nothing. Every port asserts that
  it is not happening ([concurrency.md §2](concurrency.md)).
- Unsafe pointers are used sparingly, for two reasons only: a measured
  performance need in a hot path, or a temporary need that is removed later
  ([translation-rules.md §8](translation-rules.md)).
- Callers hidden from the compiler are hunted down explicitly: selector
  strings (including ones assembled from pieces), `NSStringFromSelector`, the
  Objective-C runtime API, macros, and xib files ([hidden-callers.md](hidden-callers.md)).
- Where tests cannot reach the changed code, runtime behavior is verified by
  the lightest check that does: a temporary change to the app, or hands-on QA
  on a test VM for the most complex cases ([lifecycle.md §1](lifecycle.md)).

**Warnings and builds**

- More compiler warnings are turned on to find dangerous patterns, one file
  at a time so that nobody faces thousands of hits at once ([warnings.md](warnings.md)).
- A `switch` over an enum in Objective-C has no `default:`. Every case is
  listed so that the compiler warns when a value is added. `-Wswitch-default`
  is not used.
- The app is built for Intel as well as Apple silicon once per session,
  among the closing checks ([lifecycle.md §5](lifecycle.md); changed
  2026-11-24 from the close of each unit).
- Release builds keep Swift's safety checks ([performance.md §1](performance.md)).

**Size**

- There is no hard limit on the size of a function in a port commit, because
  there are always extenuating circumstances. A port of a function over about
  150 lines is very concerning and requires extra review ([large-code.md §2](large-code.md)).
- A temporary copy of a function may be kept in the test target only, marked
  with a distinctive comment so that all of them can be found and proven gone
  at the end ([large-code.md §2.3](large-code.md)).

**Tests**

- Tests are run locally on every commit. Fixing the disabled Xcode CI job is
  optional and not a prerequisite.
- The test suite must get faster. About 20 minutes for a full serial run is
  too long for this project ([test-speed.md](test-speed.md)).
- The fast tier runs without the address sanitizer.
- No single test should take anywhere near 114 seconds. The slowest tests are
  fixed, not merely moved to a slow tier ([test-speed.md §2](test-speed.md)).
- The thread sanitizer is fine for tests, almost none of which touch Metal.
  It is not usable when running the app ([concurrency.md §10](concurrency.md)).

**Objective-C state**

- Swift's access to Objective-C state is limited: ivars are invisible, and so
  are properties of some types. Expect to move ivars into class extensions
  with properties, sometimes into headers, and expect that in some cases even
  that is not enough ([objc-state.md §1](objc-state.md)).
- How Swift reaches each ivar is decided case by case; a property can be too
  slow for some code. Raw ivar accessors use one naming scheme, `ivar_foo`
  for the ivar `_foo`, because the natural name is often taken by an accessor
  that does something else ([objc-state.md §2](objc-state.md)).

## 4. Principles

**Translate or improve, never both.** A commit that moves code to Swift
reproduces what the Objective-C did, including its bugs. A bug found while
porting is written down (section 7) and fixed later, with the owner's word,
in its own commit with a failing test first. Mixing the two makes a
regression impossible to attribute. The one allowed addition, a thread
assertion, is in [concurrency.md §9](concurrency.md).

**Prefer canonical Swift idioms where there is no loss of correctness.** A
port keeps the Objective-C's behavior, not its spelling. Inside a method,
write what a Swift programmer would write (`==`, optional binding, `guard`,
`for ... in`, string interpolation, Swift collections' own methods) wherever
it gives the same result for every input the code can see. Keep an
Objective-C API, a cast to a Foundation class, or an awkward construction
only where a rule in [translation-rules.md](translation-rules.md) or
[traps.md](traps.md) names a real difference in behavior that the code can
reach, and say which in a comment. The interface stays as stage one
requires (below): this is about bodies, not about selectors, class names
or types seen from Objective-C. The owner, 2026-11-25: “We should update
the rules to prefer canonical swift idioms where there's no loss of
correctness”.

**Make risky semantic changes in Objective-C, before the port.** Nullability,
the move to ARC, and replacing dynamic dispatch with direct calls each change
behavior on their own. Doing them in Objective-C gives a small diff against
unchanged surrounding code. The port that follows is then closer to a
transliteration.

**Two stages.** Stage one produces Swift that still looks like Objective-C from
outside: an `NSObject` subclass with `@objc` members, the same selectors, the
same class name, the same Foundation types, the same integer widths. Stage two
makes it idiomatic (value types, generics, wider integers, Swift-native
Foundation types). Stage two only becomes possible for a type when no
Objective-C code uses it any more.

**Never make a claim you do not need.** Every annotation, type narrowing, or
assumption is a chance to be wrong. Make one only when a port in progress needs
it, and leave everything else in its current state.

**Enumerate with tools, not by reading.** Anything of the form "check every
parameter" or "find every caller" is done by a script whose output is complete
by construction, then reviewed. Careful reading does not scale to a header with
hundreds of methods and is not repeatable across agents.

**The safe direction is the default.** Where a claim can be wrong in a harmless
way or a harmful way, unproven cases get the harmless one.

**One implementation of each method at a time.** A method's Objective-C
version is deleted in the same commit that adds its Swift version. The app
never contains two versions of a method with a switch between them. A small
file moves in one commit. A large file moves a few methods at a time, with the
class living partly in each language until the last piece goes ([lifecycle.md §2](lifecycle.md)).

**Every commit builds, passes its unit's tests (and the whole suite
where gate step 3 says), and can be reverted alone. A unit is done only
when a session's closing checks have passed over it
([lifecycle.md §5](lifecycle.md)); until then it is landed, closing checks
pending.**

## 5. Commit kinds and the gate

Every migration commit is exactly one of these kinds, except the session's
document commit below. The commit message ends with a trailer naming the
unit and the kind, for example `Swift-Port: iTermFooController kind=port`.

| Kind | What it may change | Behavior change allowed |
|---|---|---|
| `tool` | Scripts, lints, test infrastructure | None in the app |
| `dossier` | A unit's files under `units/`: added when the dossier is written, deleted when the unit closes. Later changes to it ride in the unit's other commits | None |
| `test` | Adds characterization tests against existing code | None |
| `annotate` | Nullability and other header claims, plus the Swift call sites the compiler then flags | None intended; see [nullability.md](nullability.md) |
| `arc` | Moves one file from manual reference counting to ARC | None intended; see [arc.md](arc.md) |
| `undynamic` | Replaces a dynamic dispatch with a direct call, in Objective-C | None |
| `extract` | Moves a block of an oversized function into its own method, verbatim, or adds a seam for one dependency ([large-code.md §2](large-code.md)) | None |
| `decxx` | Replaces C++ in an Objective-C++ file with C or Foundation and renames it to `.m` ([objcxx.md](objcxx.md)) | None |
| `explicit` | Makes implicit conversions in Objective-C explicit and fixes strict-warning hits that do not change behavior ([warnings.md](warnings.md)) | None; generated code should be identical |
| `port` | Adds Swift and deletes the Objective-C it replaces, in the same commit: a whole small file, or a few methods of a large one ([lifecycle.md §2](lifecycle.md)) | None |
| `fix` | Fixes one logged bug, test first | Yes, the fix |
| `improve` | Stage two change to already-ported Swift | Only as stated in the message |

The gate runs on every commit:

1. `tools/build.sh` succeeds with no new warning, and none from a file the
   commit touches. Warnings are errors.
2. The targeted tests for the unit pass, run without `-parallel` so failures
   are readable.
3. The plain whole suite passes, run by
   `tools/swift_migration/whole_suite.sh` under the whole-suite lock (a
   stall is exit 124; [orchestration.md §3](orchestration.md)): on every
   full-path commit but a `dossier` commit, on the light path's `port`
   commit, and on `tool`, `fix` and `improve` commits that change app or
   test code (a commit that changes only scripts or documents is gated by
   its own tests: the migration's reading, 2026-11-24); never on the
   trivial path (the owner, 2026-11-24: “Bring it back for light and
   full”). Whole suites serialize through the lock, so each such commit
   waits its turn.
4. For `annotate`, `arc` and `port` commits on the light and full paths,
   the targeted tests also pass under the nullability and integer sanitizers ([phase0.md §4](phase0.md)).
5. A commit that adds or changes a dossier passes
   `tools/swift_migration/dossier_cap.py` ([lifecycle.md §4](lifecycle.md)).
6. New files are `git add`ed; renames use `git mv`. A port's project-file
   change is made with `tools/swift_migration/pbxproj_swap.py`
   ([lifecycle.md §3](lifecycle.md)), never `tools/add_file_to_xcodeproj.rb`.

No unit runs a sanitizer suite, the `x86_64` build or the lints. They,
with the plain whole suite once more over everything, are the closing
checks, run once at the end of each session over everything that landed
([lifecycle.md §5](lifecycle.md)), and nothing is pushed before they pass
(the owner, 2026-11-24, for the sanitizer suites, the `x86_64` build and
the lints; the plain whole suite once more is the migration's, covering
trivial units). The `x86_64` build matters because several
hazards differ between the Intel and Apple silicon slices
([warnings.md](warnings.md)) and the native build alone lets an
Intel-only error through. Rosetta is not available on the build machine,
so nothing runs for `x86_64`: build with `ARCHS=x86_64
ONLY_ACTIVE_ARCH=NO` into a separate directory and read the ported
classes' type encodings with `otool -ov`.

**Where commits go.**

- Migration commits are made directly on master. They do not go through pull
  requests: the project squashes pull requests, which would merge commits of
  different kinds into one, lose their `Swift-Port:` trailers, and break the
  rule that every commit can be reverted alone.
- History stays linear. Before pushing, fetch and rebase onto
  `origin/master`; never create a merge commit. Other checkouts push to
  master too, so fetch first and expect to rebase.
- Each commit keeps its own trailer through the rebase. If the rebase brought
  in changes to a unit's files or their dependencies, the next closing
  checks cover it.
- Agents commit locally and never push. The owner reviews each night's work
  in the morning and pushes ([workflow.md §5](workflow.md)).
- The session's document commit holds only changes that belong to no unit:
  to the documents under `docs/swift-migration/`, to the agent definitions,
  and small fixes to existing tools. It has no `Swift-Port` trailer and is
  amended while unpushed; nothing is folded into a pushed commit. A new
  tool or a Phase 0 item is its own `tool` commit, reviewed and gated. A
  unit's dossier rides in the unit's own commits (decisions.md, 2026-11-21).

Live harnesses named in `CLAUDE.md` (AI chat, attachments, Python runtime)
still apply when a unit touches those areas.

A commit that cannot pass the gate is not committed. Do not disable a test,
loosen a lint, or weaken an assertion to get through. Ask the owner,
unless a lint, comparison or other gate tool (not the build, not a test)
is defective ([workflow.md §2](workflow.md)). The one exception for a
failing test is a test that is flaky by the definition in
[test-speed.md §3](test-speed.md): it is disabled, recorded in `bugs.md`,
and reported to the owner.

## 6. The work at a glance

**Order.** Phase 0 builds the tooling. A pilot of
five to ten varied units then exercises the process end to end. After that:
the roughly 450 files with low fan-in; files with higher fan-in and subclass
trees, leaf-first; the widely imported foundations; the giant classes, by
extraction, in parallel once the pilot has proven the method; and hot paths
last. Details are in [plan.md](plan.md).

**A unit** is one implementation file with its header, or a small cluster
that cannot be separated. A unit on the full path goes through these steps,
described in [lifecycle.md](lifecycle.md); the light and trivial paths keep
a few of them ([lifecycle.md §3](lifecycle.md)):

1. **Claim.** The orchestrator records the unit as in progress.
2. **Dossier.** Everything about the unit that a port could break.
3. **Characterization tests** against the Objective-C, written so the same
   tests run against the port. Oversized functions go through
   [large-code.md](large-code.md) first.
4. **Objective-C preparation**, one commit per change: annotate
   ([nullability.md](nullability.md)), move to ARC ([arc.md](arc.md)),
   remove dynamic dispatch ([hidden-callers.md](hidden-callers.md)), remove
   C++ ([objcxx.md](objcxx.md)), make conversions explicit
   ([warnings.md](warnings.md)).
5. **Port**, following [translation-rules.md](translation-rules.md): a small
   file whole, a large file a few methods at a time. Runtime behavior that
   tests cannot reach is verified before the commit.
6. **Independent review**: the author and reviewer loop, with a fresh
   reviewer every round ([workflow.md](workflow.md)).
7. **Crash reports** and beta assertion failures from nightly and beta
   builds, attributed to ports when they arrive. Nothing waits for them.
8. **Close.** New traps and bugs are recorded and the claim is released.

## 7. Roles, records, and memory across agents

No agent remembers what another did. The repository is the memory.

**Derived, never stored:**

- Which files are still Objective-C, which are ARC, which are ported: from the
  tree.
- What happened to a unit and when: from commit trailers
  (`git log --grep 'Swift-Port: <unit>'`).
- What is next: from the inventory script's ordering.
- Remaining nullability debt: `grep -c null_unspecified`.

**Roles.**

- One orchestrating agent picks units, assigns lifecycle steps to subagents,
  runs the gate, and commits. Agents do not work on the migration
  independently of it, and subagents do not commit.
- Each change is made by an Opus subagent acting as author and reviewed by a
  different Opus subagent. A reviewer is never reused: every review is done
  by a fresh subagent that has seen neither the author's reasoning nor any
  earlier round ([workflow.md §1](workflow.md)).

**Recurring tasks** for the orchestrator, at a frequency the owner sets:

- Check for new crash reports from nightly and beta builds and attribute
  any that have arrived to ports as described in
  [lifecycle.md §1](lifecycle.md), step 7.
- Check beta assertion failures from those builds the same way.
- The closing checks, at the end of every session ([lifecycle.md §5](lifecycle.md)),
  which include the full suite under the thread sanitizer
  ([concurrency.md §10](concurrency.md)).

**Stored in `docs/swift-migration/`, because it cannot be derived:**

- `README.md` and the topic files it lists: the process.
- `decisions.md`: dated decisions and their reasons, including every change to
  this process.
- `traps.md`: the trap catalogue. One entry per pattern: what the Objective-C
  does, what a naive port does, what to write. [translation-rules.md](translation-rules.md) is its seed. Every
  unit that finds a new trap adds it before closing.
- `bugs.md`: bugs found and deliberately preserved, each with file, method,
  description, and how to reproduce. Removed when fixed.
- [orchestration.md](orchestration.md) §9: the Phase 0 checklist, since the
  state of Phase 0 cannot be derived from the tree.
- `claims.md`: units in progress, with the date and a one-line state, kept by
  the orchestrator. Its purpose is to let a new orchestrator resume, not to
  arbitrate between agents. An entry with no matching commits for several
  days is stale.
- [owner-queue.md](owner-queue.md): the items that need the owner's
  attention, so that the orchestrator never waits
  ([workflow.md §3](workflow.md)).
- `hot-paths.md`: units deferred under [performance.md §2](performance.md), with the reason.
- `reflective-sites.md`: the registry from [hidden-callers.md §2](hidden-callers.md).
- `units/<name>.md`: the dossier for a unit in progress (none on the
  trivial path). Its changes ride
  in the unit's commits; the closing commit deletes it (on the light path,
  the port commit). The history keeps it.

**The project skill** `.claude/skills/swift-migration-unit/SKILL.md`
encodes the unit lifecycle so that each orchestrator follows the same
steps and hands each subagent the same documents. It is tracked:
`.gitignore` ignores `.claude/` except `agents/` and `skills/`.

**What needs the owner.** The orchestrator does not need permission to move
to the next unit or class, or to work on the giant classes. The owner looks
at: any change to the rules in these files, anything involving a hot path,
the end of Phase 0, the move from one tier to the next, and the few other
items listed in [workflow.md §3](workflow.md). The owner also helps with
units that are parked after too many review rounds. All of these go through
[owner-queue.md](owner-queue.md). The orchestrator parks and continues; it
never blocks on the owner.
