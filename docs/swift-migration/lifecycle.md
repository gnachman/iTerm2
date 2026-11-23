# The lifecycle of a unit

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

## 1. The steps

A unit is one implementation file with its header, or a small cluster that
cannot be separated (a class with its private categories, or a subclass tree
small enough to move together).

A unit takes the light path where §3 allows it, and otherwise the full path
below; §3 also says when units may start.

One orchestrating agent runs this lifecycle. It picks units, assigns steps to
subagents, runs the gate, and commits. Subagents do not commit on their own
([README.md §7](README.md)).

**Step 1. Claim.** The orchestrator records the unit as in progress in
`claims.md` ([README.md §7](README.md)). The record is what lets a new orchestrator pick up
where the previous one stopped.

**Step 2. Dossier.** Produce the unit's dossier. It is the input to every later
step and to the reviewer. On the full path it is complete however small the
unit looks (the light path's is in §3). A section with nothing in it says
so, and how that was established. It lists:

- Public and private API, with the census output for every selector.
- The runtime snapshot of each class in the unit ([phase0.md §9](phase0.md)).
- Every xib that names a class in the unit, as a custom class or as File's
  Owner, with its outlets, actions, bindings and runtime attributes; and every
  First Responder action the unit implements ([hidden-callers.md §4](hidden-callers.md)).
- Every reflective site in the unit, and every reflective site elsewhere that
  can reach the unit ([hidden-callers.md §2](hidden-callers.md)).
- The strict-set warning report for the unit's files ([warnings.md](warnings.md)).
- Superclass, subclasses (Objective-C and Swift), categories, protocols,
  including protocols whose methods the class implements without declaring
  conformance.
- Every stored-state surface: `NSCoding`, arrangement dictionaries, user
  defaults keys, files.
- Threads and queues each method runs on, and every lock: the concurrency
  table described in [concurrency.md §10](concurrency.md).
- The ownership graph: what holds this object strongly, what it holds strongly,
  every delegate and back-pointer, every block that captures `self`.
- Every place the code depends on messaging `nil`, with what the zero result
  then causes.
- Every implicit integer or floating-point conversion, and whether overflow or
  truncation can occur with real inputs.
- The arithmetic table from [translation-rules.md §1](translation-rules.md): one row per arithmetic site that is
  not provably bounded, with the chosen treatment and the reason.
- Every implicit assumption that would make a good assertion.
- Hot-path status: is any method called per character, per cell, per frame, or
  per token? If yes, stop and move the unit to the hot-path list.
- Dependencies that are not yet annotated (the on-demand list for [nullability.md](nullability.md)).
- How runtime behavior will be verified where tests cannot reach it (see
  "Verifying runtime behavior" below).

**Step 3. Characterization tests** (`test` commits). If a function in the
unit is too large or too entangled to test or to port as it stands, follow
[large-code.md §2](large-code.md) before continuing. Written in Swift against
the `@objc` interface, so the same tests run unchanged against the port. An
Objective-C test declares the class locally with its own `@interface` and
never imports the unit's header: the port deletes the header, and
`ModernTests` cannot import `iTerm2SharedARC-Swift.h`. Cover
normal behavior, the nil-argument cases found in the dossier, boundary integer
values, and round trips of stored state. Tests must be deterministic and must
not depend on timing.

**Step 4. Objective-C preparation**, each in its own commit and each passing
the gate:

- `annotate`: nullability for the unit's own header and for the members of
  other headers that the unit uses ([nullability.md](nullability.md)).
- `arc`: move to ARC if the file is in the non-ARC target ([arc.md](arc.md)).
- `undynamic`: replace `performSelector` and friends with direct calls where
  the target is statically known ([hidden-callers.md](hidden-callers.md)).
- `explicit`: resolve the strict-set warnings for the unit's files, making
  every implicit conversion explicit ([warnings.md](warnings.md)).
- Convert plain C enums to `NS_ENUM` or `NS_OPTIONS`, and function-like macros
  the port will need into `static inline` functions or leave them in a C header
  with a Swift-callable wrapper.

**Step 5. Port** (`port` commits). Follow [translation-rules.md](translation-rules.md). A small file is ported
whole: the Swift class keeps the Objective-C name with `@objc(Name)`, the
Objective-C `.h` and `.m` are deleted in the same commit, and Objective-C
files that imported the header now import `iTerm2SharedARC-Swift.h` in their
`.m` and use `@class` in their `.h`. The project file is edited as in §3.
A large file is ported incrementally
over many commits (section 2). Steps 6 and 7 apply to each port commit.

**Verifying runtime behavior.** Tests cannot reach everything: the responder
chain with real focus, menu validation, nib loading with the real owner,
drawing, and behavior that depends on the whole app running. Before a port
commit is made, the changed code is exercised by the lightest check that
actually reaches it:

1. **A test**, where the behavior can be reached from the test host. Always
   preferred.
2. **A temporary change to the app** that exercises the code or an assertion:
   a debug menu item or launch argument that calls the ported method, or a
   beta assertion forced to run, in a build that is never committed. The
   dossier records what was changed, what was run, and what was observed.
3. **Hands-on QA on a test VM**, following `docs/vm-qa.md`, for the most
   complex cases: units with First Responder actions, units with many xib
   outlets or actions, window and tab lifecycle, drag and drop, and anything
   where focus, timing, or the interplay of several windows matters. The VM
   is vm1, which is assigned to the migration and is used without asking
   which VM to use; it is not left running, so the orchestrator asks the
   owner to start it ([workflow.md §3](workflow.md)). The dossier records
   the actions taken, with screenshots.

Agents do not drive the owner's computer. The plan for this check is part of
the dossier and is reviewed with it.

**Step 6. Independent review.** Every commit, of every kind, goes through the
author and reviewer loop in [workflow.md §1](workflow.md): an author subagent
does the work, a fresh reviewer subagent produces findings, the author
addresses them with tests, and a new reviewer looks again, until a review has
no blocking findings.

For a port, each reviewer receives, from the orchestrator, the dossier, the
deleted Objective-C, the new Swift, and the trap catalogue. It does not
receive the porter's reasoning or anything from earlier rounds. Its
instruction is to find a behavioral difference, not to confirm equivalence.
It walks each method side by side and reports every difference with an input
that shows it. It also verifies that every procedure that applies to the
commit was followed. The port is not committed until a review produces no
blocking findings.

**Step 7. Crash reports.** The port ships in nightly builds once the owner
pushes it. Nothing waits for that: units that depend on the port may be
ported as soon as it is committed. There is no soak in nightly builds,
because bug reports from nightly users are rare and a soak would tell
little. This puts more of the weight on the tests and the review in steps 3
to 6.

A report is traced to a port through crash reports, which are acted on when
they arrive ([README.md §7](README.md)). A crash in a file that has `Swift-Port:` trailers
is attributed by line: `git blame` on the crashing line, at the build's
commit, shows whether the line came from a migration commit, and the trailer
names the unit and kind. A crash attributed to a port is logged in `bugs.md`,
and dependents of that unit are not ported until it is understood. Failures
of beta assertions ([assertions.md](assertions.md)) from nightly builds are checked the same way;
they are the main signal that an arithmetic site overflowed, a conversion
changed a value or clamped, or an assumption was wrong.

Reverting a port after dependents have been ported on top of it is decided
case by case with the owner.

**Step 8. Close.** New traps discovered go into the trap catalogue. Bugs found
go into the bug ledger. The closing commit deletes the dossier, and the claim
is released.

## 2. Porting a large file incrementally

Deleting a file and adding its replacement in one commit works for a file with
a handful of methods. It does not work for a file with hundreds: the commit
could not be reviewed, tested in pieces, or reverted without losing
everything. Large files move a few methods at a time.

**Mechanism.** The class stays declared in Objective-C. A Swift file adds an
`extension` of that class. Each port commit moves a small group of methods:
the Swift versions are added to the extension as `@objc` members with the
identical selectors, and the Objective-C versions are deleted from the `.m` in
the same commit. Callers do not change, in either language. The codebase
already works this way (`PTYSession` has 26 Swift extensions).

A test on a toy class confirmed the properties this depends on: a method moved
to a Swift extension is called correctly from the remaining Objective-C,
including through a macro; the runtime's method list for the class is
unchanged; and an extension can override an inherited method. The pilot must
confirm these on a real class.

**Before the first move:**

- The file is under ARC ([arc.md](arc.md)).
- The state the methods use is reachable from Swift. A Swift extension cannot
  see Objective-C ivars at all and cannot add stored properties, and many
  properties are unusable too. [objc-state.md §1](objc-state.md) covers the limits and the remedies
  in detail; it decides which methods can move and in what order. Each remedy
  is its own preparation commit.
- Private methods that Swift will call while they are still Objective-C are
  declared in the private header.

**Choosing what to move.** Work from the leaves inward: methods that call few
other methods of the class first, so that each moved group depends mostly on
code that is already Swift or is declared in a header. Keep each group
cohesive (a feature, a `#pragma mark` section) so it has natural tests.

**What cannot move until the end:**

- Stored state, `init` methods that assign it, and `dealloc`.
- `+load` and `+initialize`.
- Methods that depend on constructs Swift lacks, until those are removed in a
  preparation commit: function-like macros, `@try`, `goto`, C++ in a `.mm`.

**The duplicate-selector hazard.** If a method exists in both the Objective-C
`@implementation` and the Swift extension, nothing fails to compile or link,
and which one runs is not defined. The same happens when a property is
declared in the class interface and its accessor is written only in a
category: the compiler synthesizes a second accessor in the main
`@implementation`. `PTYTask` had this until it was fixed on 2026-11-19. The
runtime snapshot tool ([phase0.md §9](phase0.md)) reports any selector that
appears twice in a class's method list, and the gate fails on it.

**Each move is a full port commit.** It has the dossier entries for the moved
methods, characterization tests, the runtime snapshot comparison, the
interface checks, independent review, and the gate. The dossier for a large
file is built up section by section as the work proceeds, not all at once.

**The flip.** When the `@implementation` holds only state, initializers and
`dealloc`, one last commit moves the class declaration itself to Swift:
`@objc(Name) class Name: Superclass` with stored properties, and the header is
deleted. The extensions written along the way become extensions of a Swift
class and need no change. Until the flip the class is still an Objective-C
class, so Objective-C subclasses and categories keep working; the ordering
constraints in [interop.md](interop.md) apply only at the flip.

**Size.** A port commit that translates one function of more than about 150
lines, or moves far more code than a reviewer can compare side by side, is
handled as in [large-code.md §2](large-code.md).

## 3. The light path for leaf units

Tried on the second pilot unit, `iTermColorSuggester` ("(pilot 2)" below).
Both pilot units are done. **Further units may start** (the owner,
2026-11-22: decisions.md): the night that begins at midnight on 2026-11-23
does exactly one unit, and later nights work under the ordinary usage rule
([workflow.md §4](workflow.md)). A unit that passes every qualifying check
below takes the light path.

**Which units qualify.** Every condition must hold, each established by a
tool, or by reading only where the tool says it cannot decide. The checks are
`tools/swift_migration/qualify_unit.py` ([phase0.md §12](phase0.md)),
which prints each condition PASS, FAIL or MANUAL with its evidence; the
callers' thread, which no tool decides, is answered by the orchestrator
from the call sites and recorded with `--callers-thread` (printed as
RECORDED). A MANUAL condition is one the tool cannot decide: an agent
resolves it by reading (the owner, 2026-11-21), in the unit's dossier,
quoting the tool's evidence line, what was read, and the conclusion; the
reviewer checks each one. A MANUAL that reading does not clearly settle
in the unit's favor counts as a FAIL, and a FAIL is never overridden by
reading. The tool needs only the repository and a current code
database, so it runs in any checkout; the nightly clone first brings its
own database up to date (orchestration.md, the steps after new code
arrives).

- The unit's implementation is 500 lines or fewer. (Pilot 2 was chosen
  from files of 150 lines or fewer; nothing larger has been tried.)
- Three or fewer files outside the unit use it (code database, `sends` and
  `swiftimports`). The bridging header and the unit's own tests do not
  count.
- No class in it is named in a xib, a storyboard, the sdef, an archive, the
  reflective-site registry or a key-value coding or observing site (the
  entry-point census finds nothing but ordinary sends).
- It has no C++, no `+load` or `+initialize`, no `-dealloc` that does more
  than release, no atomic property, no associated object, no swizzling.
- No instance variable of it is accessed from outside the unit (an
  `@public` ivar used through `->`): Swift cannot express a public ivar.
- It takes no lock, uses no dispatch queue and no thread API, and every
  caller is on one known thread.
- It is not on the hot-path list ([performance.md §2](performance.md)).
- It stores nothing in user defaults, a profile, an arrangement or a file.

A unit that fails any condition takes the full path of §1. So does a unit
whose author or reviewer finds, at any point, something the conditions were
meant to exclude: the unit moves to the full path and the reason is added to
this list.

**What the light path keeps.**

- The claim, and characterization tests written and seen passing against the Objective-C
  before the port, and unchanged after it (§1, step 3).
- The whole-class port in one commit, a translation.
- The runtime snapshot comparison before and after, and the comparison of
  the generated Objective-C declaration with the old header.
- A probe of each bridging boundary whose parameter type changes meaning
  (for example `NSString *` to `String?`), with any difference declared in
  the commit message (traps.md).
- One fresh reviewer, for the tests and the port together.
- The token lints, a build with no new warning, and the unit's targeted
  tests under the nullability and integer sanitizers.

**What it drops or defers.**

- The dossier is one file of at most 60 lines: what the unit is, who uses
  it, the output of the qualifying checks (generated by script), the planned
  Swift declaration, the test list, and open questions. There is no evidence
  file. It is added in the `test` commit and deleted in the port commit.
- No separate `annotate` commit: the header is deleted by the port, so its
  nullability is stated once, in the Swift. The `test` commit adds the
  header to the bridging header for the Swift tests, and the port removes
  it (pilot 2).
- Two commits, `test` then `port`. Several qualifying units with no
  dependency on each other may run at once in separate lanes. The author
  saves the `test` change set as a patch before starting the port, because
  the port undoes the bridging-header line and one index cannot hold both.
- A parameter or result the header called nonnull, or did not annotate,
  may be declared optional in the Swift when the Objective-C tolerated nil
  there; that is the safe direction, and the commit message says so. A
  nonnull claim the header did not make needs the full path's `annotate`
  evidence ([nullability.md §6](nullability.md); pilot 2).
- Until a nightly whole-suite run is a scripted step, the orchestrator
  runs the whole suite once on each port before committing it (pilot 2).
  The thread sanitizer run and the x86_64 build are deferred: the
  orchestrator runs them at the end of the session over the ports that
  landed. A failure there is fixed by a new commit or undone with
  `git revert`, never a reset or a rewrite, since the port may already be
  pushed; the night's report lists any port they have not yet covered.
- Mutation to prove each test can fail covers the behaviors the dossier
  lists, by script, not exhaustively.

**The project file.** `tools/swift_migration/pbxproj_swap.py` replaces a
`.m` and `.h` with a `.swift` and refuses anything it cannot match exactly.
The author runs it in its lane, so that the port builds and is tested
there. The orchestrator takes that change with the port (`collect
--to-index --allow-project`) if no other port landed in between, and
otherwise runs the swap again in its own checkout and stages it. Either
way the swap is staged before the gate runs, so the tree gated is the tree
committed.

Still needed: the triage of the nullability report that every test creating a `PTYSession` reaches
(bugs.md; owner queue Q23 item 12).
