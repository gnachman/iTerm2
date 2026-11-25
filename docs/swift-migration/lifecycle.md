# The lifecycle of a unit

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

## 1. The steps

A unit is one implementation file with its header, or a small cluster that
cannot be separated (a class with its private categories, or a subclass tree
small enough to move together).

A unit takes the trivial or the light path where §3 allows it, and
otherwise the full path below.

One orchestrating agent runs this lifecycle. It picks units, assigns steps to
subagents, runs the gate, and commits. Subagents do not commit on their own
([README.md §7](README.md)).

**Step 1. Claim.** The orchestrator records the unit as in progress in
`claims.md` ([README.md §7](README.md)). The record is what lets a new orchestrator pick up
where the previous one stopped.

**Step 2. Dossier.** Produce the unit's dossier. It is the input to every later
step and to the reviewer. On the full path it covers everything below
however small the unit looks, within the cap of §4 (the light path's is in
§3; the trivial path has none). A section with nothing in it is one line
saying so, and how that was established. It lists:

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

## 3. Which path: trivial, light or full

Tried first on the second pilot unit, `iTermColorSuggester` ("(pilot 2)"
below). **Further units may start** (the owner, 2026-11-22: decisions.md);
nights work under the ordinary usage rule ([workflow.md §4](workflow.md)).
The trivial path's 50-line limit and what always forces the full path,
the dossier caps (§4), the closing reserve of 75 minutes (§5), batches
smallest first with no limit but the clock, and the Apple event
comparison by day for sdef-named units were chosen by the migration and
confirmed by the owner on 2026-11-24 (“keep them as is”).

**Which path.** `tools/swift_migration/qualify_unit.py UNIT` prints the
path ([phase0.md §12](phase0.md)); UNIT is a class, or `Class(Category)`
for a category file. It needs only the repository and a current code
database; the nightly clone brings its database up to date first
(orchestration.md §1, step 4). Each condition prints PASS, FAIL or MANUAL
with its evidence; a MANUAL is one the tool cannot decide.

- **Trivial** when the trivial conditions T1 to T8 all PASS. Only the tool
  decides: a MANUAL is never settled by reading for this path. In short:
  the method and function bodies total at most 50 lines (counted from
  Clang's AST, brace to brace); no instance variable, property with
  storage, or static that is not const; no lock, queue, thread API or
  timer; compiled with ARC, or nothing in the file that ARC changes or
  rejects (then the port is also the move to ARC and no `arc` commit comes
  first); no Core Foundation ownership, even under ARC (a CF or CG
  `...Ref` returned retained, a Retain, Release or Create Rule call, a
  `__bridge_transfer` or `__bridge_retained` cast); no C++, C pointer or C
  array (a borrowed `...Ref` that only passes through, such as a
  `CGContextRef` handed to drawing calls, is allowed); no `+load`, `+initialize`,
  associated object, swizzling or `-dealloc`. Being named in the sdef, a
  xib, a selector string or the registry does not stop a trivial unit; the
  trivial path's runtime evidence covers it instead. Whatever its size, a
  unit takes the full path when it is a hot path, stores anything (user
  defaults, a profile, an arrangement, a file, Core Data), is archived, or
  has an Objective-C subclass.
- **Light** when it is not trivial and every light condition below holds
  (each MANUAL settled by an agent's reading, the owner, 2026-11-21: in the
  dossier, quoting the tool's evidence line, what was read and the
  conclusion; the reviewer checks each. A MANUAL that reading does not
  clearly settle in the unit's favour counts as a FAIL, and a FAIL is never
  overridden). The callers' thread, which no tool decides, is answered by
  the orchestrator from the call sites and recorded with
  `--callers-thread` (printed as RECORDED). A category unit is never light:
  the light conditions are written for a class.
- **Full** otherwise.

The light conditions:

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

A unit whose author or reviewer finds, at any point, something its path's
conditions were meant to exclude moves to a heavier path (trivial to light
if it meets the light conditions, otherwise to full), and the reason is
added to these conditions.

Translate-or-improve, the trap catalogue, the nullability rules of the
light path below ([nullability.md §6](nullability.md)) and the
project-file tool apply to every path unchanged.

**A unit named in `iTerm2.sdef`**, on any path, also gets an Apple event
comparison before and after the port: `osascript` sends the unit's
commands and property reads to the build under test addressed by its
full path (`tell application "/full/path/to/Build/Development/iTerm2.app"`;
the owner, 2026-11-24: “You can safely run applescript locally by saying
`tell "/full/path/to/build/i/want/to/test"`”), launched with `-suite
<last path component of the lane>`, and the outputs are compared with
identifiers masked. Afterwards the app and its session daemons (iTermServer
under `~/Library/Application Support/<suite>/`) are stopped by pid,
identified by the build path and the suite, never by name. The night
session may not run `osascript`, so at night such a unit stays *landed,
closing checks pending* with the note "AppleScript comparison owed", and
the orchestrator runs the comparison by day before the unit is called
done. The first, for `iTermApplication+Scripting` on 2026-11-24 by hand,
sent 16 commands and got identical answers before and after.

### The trivial path

1. **Claim** it in `claims.md` with the path `trivial`.
2. **No dossier.** The commit message carries short unit notes instead:
   what the unit is; the `qualify_unit.py` path line and body-line count;
   each reflective entry (from the entry-point census, `entry_points.py`,
   for the unit's class and selectors: a key, a selector string, a
   scripting specifier, a xib) with the test that covers it; the runtime
   snapshot result; the number of characterization tests seen passing
   against the Objective-C before the port, and how each was seen
   failing; a bridging probe for each parameter or result whose type
   changes meaning across the bridge (for example `NSString *` to
   `String?`; traps.md); for a thread assertion, which case of
   [concurrency.md §9](concurrency.md) applies; anything surprising.
3. **One author, one lane, one `port` commit** holding the tests and the
   port together. Tests first still holds inside the lane: the author
   writes the characterization tests (§1, step 3), one per reflective
   entry going through the door the system uses (key-value coding, a
   selector built from a string, an object specifier), runs them against
   the Objective-C and sees them pass, then sees each fail once against a
   deliberately broken Objective-C body (one hand edit per method,
   reverted; no mutation script is required). It takes the runtime
   snapshot of each class (`runtime_snapshot.sh`), ports, runs the same
   tests, and takes the snapshot again: `compare_runtime_snapshots.sh`
   passes, a class that stays in Objective-C (a category's class) has
   identical snapshots, and each CHECK AGAINST THE SOURCE line is answered
   in the unit notes. The bridging-header line the tests need against the
   Objective-C is added in the lane and removed by the port, so the commit
   has none. The project file is swapped as below.
4. **One review** by a fresh reviewer given the diff, the deleted
   Objective-C, the new Swift, the qualifying output, the snapshot
   comparison, `traps.md` and `translation-rules.md`. Since the trivial
   path has no callers'-thread condition, the reviewer compares every
   block's captures (strong, weak, `self`) and every observer or
   notification registration and removal with the Objective-C. Another
   round, with another fresh reviewer, only if a blocking finding stood.
5. **The gate** per unit: the build and the unit's targeted tests
   ([README.md §5](README.md)). No whole suite (the owner, 2026-11-24,
   brought it back for light and full only), sanitizer run, `x86_64`
   build or lint per unit: those are the session's closing checks (§5).
6. **Commit**, then the unit is *landed, closing checks pending* until the
   session's closing checks pass.

Several trivial units may be done in one session, each its own commit
with its own review, under one set of closing checks
([orchestration.md §2](orchestration.md)). At night, units with no
dependency on each other may be authored at once in separate lanes, at
most three (the owner, 2026-11-24: “allow it”; the bound is the
migration's); by day one at a time. Commits land one at a time, each
gated on the tree it lands on.

### The light path

**What it keeps.**

- The claim, and characterization tests written and seen passing against the Objective-C
  before the port, and unchanged after it (§1, step 3).
- The whole-class port in one commit, a translation.
- The runtime snapshot comparison before and after, and the comparison of
  the generated Objective-C declaration with the old header.
- A probe of each bridging boundary whose parameter type changes meaning
  (for example `NSString *` to `String?`), with any difference declared in
  the commit message (traps.md).
- One fresh reviewer, for the tests and the port together.
- A build with no new warning, the plain whole suite on the `port` commit
  ([README.md §5](README.md), step 3), and the unit's targeted tests also
  pass under the nullability and integer sanitizers ([phase0.md §4](phase0.md);
  [README.md §5](README.md), step 4).

**What it drops or defers.**

- The dossier is one file of at most 60 lines (§4): what the unit is, who
  uses it, the output of the qualifying checks (generated by script), the
  planned Swift declaration, the test list, and open questions. There is
  no evidence file. It is added in the `test` commit and deleted in the
  port commit.
- No separate `annotate` commit: the header is deleted by the port, so its
  nullability is stated once, in the Swift. The `test` commit adds the
  header to the bridging header for the Swift tests, and the port removes
  it (pilot 2).
- Two commits, `test` then `port`. Several qualifying units with no
  dependency on each other may run at once in separate lanes (at night at
  most three, by day one at a time: [orchestration.md §2](orchestration.md)).
  The author
  saves the `test` change set as a patch before starting the port, because
  the port undoes the bridging-header line and one index cannot hold both.
- A parameter or result the header called nonnull, or did not annotate,
  may be declared optional in the Swift when the Objective-C tolerated nil
  there; that is the safe direction, and the commit message says so. A
  nonnull claim the header did not make needs the full path's `annotate`
  evidence ([nullability.md §6](nullability.md); pilot 2).
- No sanitizer suite, `x86_64` build or lint per unit: the session's
  closing checks (§5) cover them.
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

## 4. Dossier length

A dossier lists what was found. A check that found nothing gets one line
saying so and how that was established, never more. The cap, evidence
files included: a trivial unit has no dossier; a light unit's is at most
60 lines; a full unit's is at most one line per line of its
implementation files, never less than 100 or more than 600. A dossier
goes over the cap only with a line `Over the cap: <reason>` among its
first ten lines. `tools/swift_migration/dossier_cap.py DOSSIER --path
light|full [--implementation FILE...]` checks it, in the gate of every
commit that adds or changes a dossier ([README.md §5](README.md)).

## 5. Closing checks, once per session

The heavy checks run once at the end of a session, over everything that
landed in it, on every path. The owner decided on 2026-11-24 that the
sanitizer suites, the `x86_64` build and the lints run once per session
over everything that landed, and that light and full units' commits also
pass the plain whole suite ([README.md §5](README.md), step 3; “Bring it
back for light and full”); it runs here once more over everything,
covering the trivial units. The orchestrator runs them in the full-suite lane on `HEAD`, in this order, one at a time, each
under the whole-suite lock with its stall watchdog, waiting on each only
with `suite_guard.py wait` ([orchestration.md §3](orchestration.md),
"Heavy jobs and the machine"). Measured durations on 2026-11-24 are in
brackets; about an hour in all.

1. The plain whole suite: `tools/swift_migration/whole_suite.sh` [9 min].
2. `sanitizer_tests.sh nullability` with no test names: it does not abort,
   and fails on a report outside the nullability baseline
   ([nullability.md §7](nullability.md); owner-queue.md Q26) [7.5 min].
3. `sanitizer_tests.sh integer` [7 min].
4. `sanitizer_tests.sh thread`, serially, never `--parallel`
   ([thread-baseline.md](thread-baseline.md)) [17 min].
5. The `x86_64` build, with no warnings ([README.md §5](README.md)) [1 to
   8 min].
6. The lints and the code database: `capture_compile_commands.sh`,
   `codedb.py update --accept-removals`, then the lints of
   [phase0.md §6](phase0.md), "Where they run", over the session's port
   commits [about 10 min].

A fix commit after a failed check re-runs that check and every check after
it in this order. If the closing checks' start time has already passed when
a session starts (a short night), the session runs only the pending
closing checks and ports nothing. A unit named in the sdef also owes its
Apple event comparison (§3), which only a day session can run.

**A failure** is attributed to a unit by its files: the failing test's
subject, the warning's or the finding's file, against the files of the
session's commits (`git log --grep 'Swift-Port:'`). It is fixed by a new
commit of that unit through the loop and the gate, or the unit's commits
are undone with `git revert`; never a reset or a rewrite of history. A
failure that the session's baseline run also showed (orchestration.md §1,
step 4) is not the session's: it goes to `bugs.md`.

**Until they pass, the units are pending.** Between a port's commit and the
closing checks the tree is gated only by the build, the unit's targeted
tests and, off the trivial path, the whole suite. A unit committed in the
session is *landed, closing checks pending* in `claims.md` and in the report until the checks pass over it. A session
does not end, and the owner is not told a unit is done, before the closing
checks ran. A session that cannot run them all (the clean stop, usage)
leaves its units pending, says which checks did not run, and the next
session runs the closing checks before it starts any unit.

**The report** records each check with its result, duration and run
directory, the units it covered, each failure with its fix or revert, and
any check that did not run.
