# Orchestrator runbook

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

This file is for the orchestrating agent. It assumes you have no memory of any
earlier session. Following it from the top is enough to pick up the work
wherever it was left. The other files say what the rules are; this one says
what to do, in order.

## 1. Cold start

Do these every time a session begins, before anything else.

1. Read [README.md](README.md) in full, then [workflow.md](workflow.md) and
   [lifecycle.md](lifecycle.md) in full.
2. Check the usage budget ([workflow.md §4](workflow.md)): run
   `claude /usage`, read the "all models" line, and compute tonight's cap
   from the reset time. If usage is at or above the cap, or the line does
   not parse, write the report (section 8) and stop.
   `python3 tools/swift_migration/usage_check.py --run` does this reading
   and computation; its exit status is 0 when work may start, 1 at or above
   the cap, and 2 when usage is unknown.
3. Look at the working tree: `git status`. It should be clean apart from
   files the owner leaves untracked. If there are uncommitted migration
   changes, an earlier run stopped badly: read `claims.md`, save the changes
   as a patch under `tmp/`, restore the tree, and record what you found.
   In the unattended night this case does not reach you as things stand:
   `nightly_clone.sh refresh` refuses a clone with uncommitted or untracked
   changes (exit 8) and the night does not start, so the owner finds it in
   the morning. Which of the two should handle it is a question for the
   owner. Then run `tools/swift_migration/lane_clone.py status` and free
   lanes held by a dead session with `release --stale` (section 3, "Build
   lanes").
4. In the unattended night, `nightly_start.sh` has already refreshed the
   clone before you start ([workflow.md §5](workflow.md)): it fetched the
   project's `origin/master` from GitHub into the clone's read-only mirror,
   then fast-forwarded the clone to it, kept the clone's commits when the
   clone was strictly ahead, reset the clone to it when everything the
   clone's commits change was already upstream, or rebased the clone's own
   commits onto it. Never fetch, rebase or merge yourself. What it did is
   in the run's `refresh.status` file, which the prompt names (and in
   `nightly_start.log`, prefixed `refresh:`), one line each:
   - `nightly_clone: upstream: refreshed: ...`, or
     `nightly_clone: upstream: NOT REFRESHED: ...` when GitHub could not be
     reached: the night goes on with `origin/master` as old as the last
     fetch that worked, and the night's report says so;
   - `nightly_clone: upstream-commits: none`, or
     `nightly_clone: upstream-commits: taken <base>..<new> (<n> commits)`;
   - `nightly_clone: rebased: <n> commits onto <sha> ...`, or
     `nightly_clone: already-upstream: reset to <sha> ...`;
   - `nightly_clone: submodule-stale: <path>: ...` for a submodule left at
     its old commit because the commit the new code records could not be
     fetched (the build may fail).

   If upstream commits were taken, or a rebase or reset happened, new code
   arrived. Before starting any unit, bring what is derived from the code
   up to date, in this order. Everything named here lives inside the
   clone and is ignored by git: the code database and its inputs in
   `<clone>/tmp/codedb/` (the compile command fragments in
   `cdb-fragments/`, `compile_commands.jsonl`, the database
   `codedb.sqlite`), and build products in `<clone>/Build/`.
   1. **Compile commands**, if the capture is stale.
      `tools/swift_migration/codedb/capture_compile_commands.sh` runs one
      clean Development build of the ModernTests scheme with clang writing a
      compile command fragment for every file it compiles; its header says
      to run it again whenever source files are added or removed or compile
      flags change, and `codedb.py update` reports when the compile
      database no longer matches the project. It builds in, and writes the
      database inputs of, the checkout it is run from, so it is run in the
      clone (the database belongs to the clone; a lane has none). It counts
      as one of the three builds that may run at once, so run it before
      starting agents. A whole clean build takes as long as any clean build
      of the app.
   2. **`codedb.py update`**. Incremental: it extracts every Objective-C
      unit that is not current and reads again every Swift module that is
      not current; a schema change, or a changed compiler, extractor or SDK,
      makes every unit stale. After a port that deleted files, run it with
      `--accept-removals`. Until the database is current, a query
      answers but exits 3 ("incomplete": some unit is not current) instead
      of 0 or 1 (`codedb.py --help`, "Exit status" and "Unit states"). A
      whole-tree extraction took about 7 minutes on a quiet machine and 20
      to 30 minutes under load; an incremental update takes time in
      proportion to the units that changed.
   3. **`codedb.py macrolint`** (every macro of the kinds in
      [hidden-callers.md](hidden-callers.md) §6 has a current row in
      `macro-classification.tsv`) and **`codedb.py crosscheck`** (each
      Objective-C unit against its object file under `Build/`; exit 0
      nothing unexplained, 1 unexplained differences, 3 some units not
      compared, for example because their object is older than their
      sources, 2 error). See `codedb.py --help` for their options.
   4. **The run-time method list**, if the OS build changed since it was
      written: `tools/swift_migration/sdk_selectors.py --runtime-methods
      OUTPUT` writes it, with a `# os: NAME VERSION (BUILD)` line to compare
      with `sw_vers`. The entry-point census reads it
      (`entry_points.py --runtime-methods FILE`). `nightly_clone.sh setup`
      copies only `tmp/parked/` and `tmp/stored-state-corpus/` into the
      clone, so the clone has no list until one is written under
      `<clone>/tmp/`.
   5. **`inventory.py summary`**, which recomputes the progress measures
      from the tree; nothing is stored.
   6. **The whole-suite baseline**, if the new commits touched `sources/`
      or `ModernTests/` (`git diff --stat <base>..<new> -- sources
      ModernTests`): run `tools/run_tests.expect -parallel` in the
      full-suite lane (`lane_clone.py acquire --full-suite`) on the new
      `HEAD`, so that a failure that arrived with the new code is recorded
      as such and not blamed on the night's first unit. If those commits
      touched a unit in progress or its dependencies, also run gate steps 7
      and 8 ([README.md §5](README.md)) for it.
   7. **Lanes.** `nightly_start.sh` released lanes left held by a dead
      session after the refresh; a free lane is reset to the new `HEAD`
      when it is next acquired. A lane you still hold from before is
      released and acquired again.
5. Read [owner-queue.md](owner-queue.md). Act on everything under
   "Answered": do what the answer says, record any resulting rule in
   `decisions.md`, and remove the item.
6. Read `claims.md` to see what was in progress and what is parked.
7. Check for new crash reports and beta assertion failures, and attribute
   any that have arrived ([lifecycle.md §1](lifecycle.md), step 7).
8. Decide what to work on (section 2).

Never wait for the owner. If something needs the owner, add it to
[owner-queue.md](owner-queue.md), park what depends on it, and continue with
other work.

## 2. Deciding what to work on

Work out which stage the migration is in, in this order:

1. **Phase 0 is not finished** if any box in section 9 is unchecked. Work on
   the first unchecked item whose dependencies are done. Phase 0 items are
   `tool` and `test` commits and go through the same author and reviewer
   loop as everything else.
2. **Phase 0 is finished but the owner has not approved its end.** Queue the
   request under "Needs a decision" if it is not already there. Meanwhile,
   improve Phase 0 tooling, work on test speed, and prepare dossiers for
   pilot candidates. Do not start pilot ports.
3. **After the two pilot units**, no further unit starts until the owner
   says so ([lifecycle.md §3](lifecycle.md)); meanwhile work on Phase 0.
4. **Once the owner allows further units.** Resume anything in `claims.md` that is in progress
   and not parked. Otherwise take the next eligible unit from the inventory
   script's ordering. A unit is eligible when:
   - it is in the current tier, or it is a giant-class extraction;
   - it is not a hot path, and not listed in `hot-paths.md`;
   - its subclasses and categories are done
     ([interop.md](interop.md));
   - it is not parked.

   Assign its path as [lifecycle.md §3](lifecycle.md) says, including
   where the light path may be assigned. Light-path units with no
   dependency on each other may run at once, each in its own lane.
5. **The current tier is nearly exhausted.** Queue a tier-transition request
   in [owner-queue.md](owner-queue.md) with what was done and any crash
   reports attributed to its ports. Keep working on what remains, on
   giant-class extractions, and on parked units whose queue items have been
   answered.

## 3. Running one step of a unit

A unit's steps are in [lifecycle.md §1](lifecycle.md). Each step that
produces a commit goes through this sequence.

1. **Check the budget** (section 1, step 2). Do this before starting every
   subagent and before every gate run.
2. **Record the step** in `claims.md`: unit, step, date, round 1.
3. **Start the author** (section 4).
4. **Start a fresh reviewer** (section 5) on what the author produced.
5. **Read the findings.** For each blocking finding, decide whether it
   stands. If the author disputes one, weigh the evidence yourself; a test
   that would fail if the finding were right settles it. Record rejected
   findings in the dossier under "Considered and rejected".
6. **If there are blocking findings that stand**, send them to the author,
   then go back to step 4 with a new reviewer. Update the round in
   `claims.md`.
7. **After the fourth review with blocking findings**, consider splitting
   the step into smaller commits. If that is not possible, park the unit
   ([workflow.md §2](workflow.md)) and return to section 2.
8. **When a review has no blocking findings**, run the gate
   ([README.md §5](README.md)), steps 1 to 6. You run it, not a subagent,
   in the full-suite lane ("Build lanes" below).
   If the gate fails, the failure goes back to the author as a finding and
   the loop continues.
9. **Commit** (section 6).
10. **At the close of a unit**, run gate steps 7 and 8 (for light-path
    units, as [lifecycle.md §3](lifecycle.md) defers them), do the closing
    updates in [lifecycle.md §1](lifecycle.md), step 8, and remove the
    unit from `claims.md`.

**Build lanes.** Agents that change code or run builds each work in their
own checkout, so that they neither wait on one shared `Build/` nor
overwrite each other's working tree (decisions.md, 2026-11-20). The tool is
`tools/swift_migration/lane_clone.py`, run from your own checkout (the
owner's checkout in the day, the nightly clone at night); its header is
the manual.

- Each author or reviewer that builds or tests works in a lane: run
  `lane_clone.py acquire --purpose "<unit> <role>"` and give the agent the
  path it prints (section 4). For a reviewer, or an author in a later
  round, add `--apply-staged <the unit's paths>` so that the lane starts
  from the change as it stands in your index.
- At most three lanes build at once. The highest-numbered lane is kept for
  the gate's full-suite run and is handed out only to
  `acquire --full-suite`; you run the gate (section 3, step 8) there, with
  `--apply-staged` for the unit's paths.
- Take an agent's change with `lane_clone.py collect N` to read it, then
  `collect N --to-index`, which applies it to your index and working tree
  and refuses a patch that does not apply cleanly, one that changes a
  submodule, and one that touches an Xcode project file unless you pass
  `--allow-project` after reading that part of the diff. Then free the lane
  with `release N`.
- Commit by explicit pathspec (`git commit -F <message file> -- <paths>`),
  never everything staged: other units' changes share the index. Note that
  `git commit -- <paths>` commits the working-tree version of those paths,
  not what is staged for them. When two units' changes have been merged into
  one file, either commit the two units together, or split them with a
  temporary index: `GIT_INDEX_FILE=<tmp> git read-tree HEAD`, then
  `GIT_INDEX_FILE=<tmp> git apply --cached <one unit's patch>` (the
  output of `collect N`, saved under `tmp/` before the lane is released),
  then `GIT_INDEX_FILE=<tmp> git commit -F <message file>`.
- At the start of a session, run `lane_clone.py status`: a lane whose holder
  is dead (an earlier session that was killed or ended) shows as `stale`.
  `release --stale` frees every such lane and saves its uncollected work as
  patches under `<lanes>/saved/`, naming each one. In the unattended night
  `nightly_start.sh` has already done this before you start and logged it
  in `nightly_start.log`.
- A lane has no code database of its own. Agents query your checkout's
  database read-only by its absolute path, with your checkout's
  `codedb.py`: a `codedb.py` of another schema version refuses to query
  it, and its `update` would rebuild it. The lane instructions in the
  tool's header say this. A lane whose code database tools differ from
  your checkout's (a unit that changes the extractor) builds and passes
  its own binary with `--extractor`, and its tests name a lane-local
  binary: `codedb.py` refuses to rebuild another checkout's binary, since
  a lane's tests once replaced the main checkout's during a re-extraction.
- Lanes live beside your checkout, in `<checkout>.lanes/`. The nightly
  clone's are in `<clone>.lanes/`, which the session is allowed to edit
  ([workflow.md §4](workflow.md)).

You may run several units at once when they do not touch the same files.
Every commit must be built and tested against the tree it lands on: the
gate runs in the full-suite lane on your current `HEAD` with the unit's
change applied. The project-file swap is staged before the gate
([lifecycle.md §3](lifecycle.md), "The project file").

## 4. Briefing the author

The author is an Opus subagent. It knows nothing except what you give it.
Give it:

- The unit, the step, and the commit kind ([README.md §5](README.md)).
- The instruction to read [README.md](README.md) in full first, then the
  topic files for this step, which you name explicitly from the table in
  [README.md §1](README.md).
- The dossier (`units/<name>.md`), or for step 2, the instruction to write
  it in full.
- `traps.md` and `bugs.md`.
- The exact scope: which files and which methods, and what must not be
  touched.
- If it builds or tests, its lane: the path `lane_clone.py acquire`
  printed, and the lane instructions from the header of
  `tools/swift_migration/lane_clone.py`, pasted with `LANE` replaced by
  that path (section 3, "Build lanes").
- What to return: the change in the working tree, the tests it added, the
  commands it ran with their results, the proposed commit message with its
  trailer, and anything it was unsure about.
The standing instructions are in the agent definition
(`.claude/agents/migration-author.md`). Send findings back verbatim.

## 5. Briefing the reviewer

The reviewer is a different Opus subagent, new for every review. Never
continue or reuse a reviewer. Give it:

- The instruction to read [README.md](README.md) in full first, then the
  topic files for this commit kind, named explicitly.
- The dossier, the diff, the code before and after, `traps.md`, and the
  tool outputs the commit kind requires (runtime snapshot, interface
  snapshot, lint results, coverage report).
- Its task, in two parts: find anything incorrect, and verify that every
  documented procedure that applies to this commit was followed. For a
  `port`, the first instruction is to find a behavioral difference with an
  input that shows it ([lifecycle.md §1](lifecycle.md), step 6).
- If it builds or tests, its lane, acquired with `--apply-staged` for the
  unit's paths, and the lane instructions, as for the author (section 4).
- The format for findings: each one labeled blocking or non-blocking
  ([workflow.md §1](workflow.md)), with the file and line, what is wrong,
  and how to check it.
- The instruction that it is not there to confirm the change. A review with
  no findings must say what it checked.

Do not give it: the author's explanation of its reasoning, earlier findings,
the author's responses to earlier findings, or the number of the round.
Rejected findings reach it only through the dossier's "Considered and
rejected" section.

## 6. Committing

- Commit only what has passed the loop and the gate.
- One commit is exactly one kind ([README.md §5](README.md)), apart from
  the session's document commit.
- Stage files by name. Never `git add` a submodule. `git add` new files as
  soon as they are created.
- Changes that belong to no unit go in the session's one document commit;
  a new tool or Phase 0 item is its own `tool` commit
  ([README.md §5](README.md), "Where commits go").
- The message says what changed and why. Every commit but the session's
  document commit ends with the trailer `Swift-Port: <unit> kind=<kind>`. An oversized port also carries
  `Oversize-Port: <function>, <lines>`
  ([large-code.md §2](large-code.md)).
- Follow the owner's rules for commit messages: no em dashes, and no
  co-author line.
- Commit on master. Do not create a branch. Do not push, ever.
- After a `port` commit that lands a feature or fix visible to users, the
  release notes rule in `CLAUDE.md` applies. A faithful port changes no
  behavior and needs no note; a `fix` commit usually does.

## 7. Stopping

Stop when the budget is reached, when usage cannot be read, when the owner
begins using the checkout, or when there is no eligible work. Follow the
five steps under "Stopping cleanly" in [workflow.md §4](workflow.md): start
nothing new, let running subagents finish, commit what is complete, save
other work as a patch and record it in `claims.md`, and restore the tree.

Before you finish, confirm: `git status` is clean, the tree builds, every
unit you touched has an accurate entry in `claims.md` or none, and
everything needing the owner is in [owner-queue.md](owner-queue.md).

## 8. The night's report

Write it to `tmp/swift-migration-night-<date>.md`. It is not committed. Its
contents are listed in [workflow.md §5](workflow.md). Write it even when no
work was done, with the reason.

## 9. Phase 0 checklist

The state of Phase 0 cannot be derived from the tree, so it is kept here.
Check a box in the commit that completes the item. Details of each tool are
in [phase0.md](phase0.md) unless another file is named.

Before anything else:

- [x] The process files and the `CLAUDE.md` change are committed.

First, because everything else uses them:

- [x] Inventory script, core ([phase0.md §1](phase0.md)): scope, targets
      and ARC, counts, relations, hazards, trailer history, the progress
      measures ([README.md §2](README.md)), the Objective-C++ classes
      ([objcxx.md](objcxx.md)), and the leaf ordering with its deferred
      lists. Split from one item after three review rounds.
- [x] Code database, extraction: compile commands captured from a real
      build, and an extractor on upstream LLVM (not Xcode's tooling) that
      writes translation units with digests of their inputs, and message
      sends, to SQLite, checked against the app's object files
      ([decisions.md](decisions.md), 2026-11-19). Kept small on purpose; the
      tables below are added one item at a time.
- [x] Code database, methods and selectors: method declarations and
      definitions, what each overrides or satisfies, properties with their
      accessor selectors, `@selector` expressions, and reflective calls
      with their argument kind; the queries `methods`, `selrefs`,
      `reflective` and `reach`.
- [x] Code database, state: ivars and file-level statics with their types
      and ownership, ivar and property references with their use kind,
      macro definitions and expansions, and skipped preprocessor ranges as
      a table. Needed by the ivar table.
- [x] Code database, Swift references: the Swift compiler's JSON AST dump
      for each module, streamed into tables of references to Objective-C
      declarations (calls, properties, `#selector`, key paths, dynamic
      lookups), Swift declarations visible to Objective-C with their
      selectors, and conformances ([decisions.md](decisions.md),
      2026-11-19). The capture keeps the build log and each module's file
      list.
- [x] Code database, what Swift can import: the importable declarations of
      each bridging header, from `swift-symbolgraph-extract`.
- [x] Code database, other projects: capture and extract the in-repository
      code that other Xcode projects build into frameworks the app embeds
      (`ColorPicker/`, and CoreParse from `submodules/CoreParse`, the source of
      `ThirdParty/CoreParse.framework`), so that callers in it are
      parsed and not only searched as text.
- [x] Code database, cross-check: every selector an object file sends is
      explained by the database, and the reverse.
- [x] Inventory scope: add `SignedArchive/`, `pidinfo/`,
      `iTerm2SandboxedWorker/` and the other directories in
      [README.md §2](README.md) to the inventory's scope, with its counts
      and leaf ordering (owner queue Q13).
- [x] Ivar and static table per class ([objc-state.md](objc-state.md)),
      rebuilt as queries on the code database, with types and importability
      from the compiler. The text-based `inventory_state.py`, parked after
      four review rounds, is discarded by the owner's decision (owner queue
      P1); its ivar list, if the saved patch still exists, is only a
      comparison for the new one.
- [x] Inventory verify: the inventory's parsed classes, ivars and methods
      compared with the code database and the runtime snapshot.
- [x] Runtime snapshot of a class, with the duplicate-selector check
      ([phase0.md §9](phase0.md)).
- [x] Ivar ownership in the runtime snapshot, from the runtime's strong and
      weak ivar layouts. Split out of the snapshot tool after four review
      rounds: it must never print "not owned" for a pointer to something
      that holds objects, for C++ members the layout omits, or for a struct
      with both strong and weak members. A saved starting point is at
      `tmp/phase0-snapshot-with-ivar-ownership.patch` if it still exists.
- [x] Runtime snapshot comparison for a class that changes language, by the
      rule "identical in meaning" ([phase0.md §9](phase0.md), decided in
      owner queue R4): classify the systematic differences between an
      Objective-C class and its Swift replacement, fail on the rest, and
      list what needs a check against the source. Needed before any
      whole-class port.

Then, in any order that respects dependencies:

- [x] Entry-point census ([phase0.md §2](phase0.md)), as queries on the
      code database for everything the compiler sees, plus the XML and text
      search for xibs, storyboards, the sdef, plists, Core Data models and
      names built at run time. A text-only version reached its second
      review; its XML parsing, hit classes and exit status are kept, and its
      lexers and macro model are replaced.
- [x] Reflective-site registry (`reflective-sites.md`) built by reading
      every hit, and the macro classification with its lint
      ([hidden-callers.md](hidden-callers.md)).
- [x] Binding tests for xibs, the sdef, and archive class names
      ([phase0.md §3](phase0.md)).
- [x] Sanitizer configurations: nullability, the integer group, and the
      thread sanitizer for tests ([phase0.md §4](phase0.md)).
- [x] First triage of nullability sanitizer reports in the headers that are
      already annotated. The triage and the 16-unit fix plan are in
      `nullability-triage.md`; carrying the plan out is separate work.
- [x] Thread sanitizer baseline of existing races
      ([concurrency.md §10](concurrency.md)).
- [x] Integer sanitizer discovery run
      ([translation-rules.md §1](translation-rules.md)).
- [x] Swift interface snapshot ([phase0.md §5](phase0.md)).
- [x] Lints for migration Swift, and how they apply only to migration files
      ([phase0.md §6](phase0.md)).
- [x] Helper library: `it_betaAssert`, the arithmetic and narrowing
      helpers, float-to-integer conversion, and the synchronized helper
      ([phase0.md §7](phase0.md)).
- [x] `iTermStrictWarnings.h` and the warning survey on both architectures
      ([warnings.md](warnings.md)).
- [x] Pure-move checker ([large-code.md §2.2](large-code.md)).
- [x] Per-function coverage report: the uncovered lines of one named
      function, from a test run with coverage
      ([large-code.md §2.1](large-code.md)).
- [x] Extraction analysis beyond text: the control-flow exits and the
      locals written in an extracted block, from the code database, and the
      comparison of compiled code before and after an extraction
      ([large-code.md §2.2](large-code.md)).
- [x] Instance census and lifetime witness tests for session, tab, and
      window ([lifetimes.md](lifetimes.md)).
- [x] Test-log timing script ([test-speed.md](test-speed.md)).
- [x] Tests over five seconds fixed, starting with the two slowest, aiming
      for under 1 second each ([test-speed.md §2](test-speed.md)): made
      fast, or in the slow tier with the reason
      ([test-tiers.md §4](test-tiers.md)).
- [x] Fast test tier defined, without the address sanitizer, with its time
      budget (77 s: [test-tiers.md §1](test-tiers.md)).
- [x] Nil-lock assertions added to the existing Objective-C
      ([concurrency.md §2](concurrency.md)).
- [x] Performance and memory baselines ([phase0.md §8](phase0.md);
      the numbers are in [performance.md §3](performance.md)).
- [x] Stored-state corpus ([stored-state.md](stored-state.md)), produced
      by agents: the current version with `-suite` and AppleScript or the
      Python API, older releases on vm1. The owner is needed only to start
      vm1.
- [x] `traps.md`, `bugs.md`, `claims.md`, and `hot-paths.md` created.
- [x] Agent definitions for the author and the reviewer, pinned to Opus.
- [ ] The nightly start mechanism and the usage check, set up and dry-run
      (proving it over several nights follows Phase 0: decisions.md,
      2026-11-20) ([workflow.md §4](workflow.md)).
- [x] The end of Phase 0 approved by the owner: on 2026-11-21 he approved
      starting the pilot with the unticked items above continuing
      alongside it (decisions.md).

After the pilot:

- [x] Process files revised from what the pilot found.
- [x] The project skill that encodes the lifecycle
      ([README.md §7](README.md)).

## 10. When something goes wrong

| Situation | What to do |
|---|---|
| The gate fails on a commit that passed review | Treat the failure as a blocking finding and continue the loop. Never loosen the gate |
| A test is flaky | Do not retry until it passes. Decide whether it is flaky by the definition in [test-speed.md §3](test-speed.md). If it is, disable it, record it in `bugs.md` with how it failed and when, and queue it for the owner, who has another agent debug it. If it is not, it is a failure: treat it as a blocking finding |
| `xcodebuild` hangs before printing anything, and a sample shows it waiting in CoreDevice | Run `killall CoreDeviceService`; the system restarts it on demand. Then retry |
| A tool from Phase 0 gives a wrong answer | Stop relying on it, fix the tool in a `tool` commit through the loop, and recheck the units that used it since it broke |
| A rule in these files seems wrong | Do not work around it. Queue it under "Rule changes proposed" with the evidence, park what depends on it, and continue elsewhere |
| A unit turns out to be a hot path | Add it to `hot-paths.md` with the reason, drop the claim, and move on |
| The clone's commits could not be rebased onto `origin/master` (a conflict, a merge commit, a submodule pointer change), or the upstream was force-pushed | The refresh refuses before the night starts (exit 9), leaves the clone as it was, keeps its old tip under `refs/nightly/pre-rebase/`, and says in the log which commit and which files; nothing runs. The owner rebases the clone by hand or sets its commits aside with `nightly_clone.sh reset`; after a force-push, `nightly_clone.sh reset --accept-rewritten-upstream` |
| A crash report is attributed to a port | Log it in `bugs.md`, stop porting that unit's dependents, and queue it for the owner with the attribution |
| A subagent does something outside its instructions (commits, pushes, edits the process files) | Undo what can be undone locally, record it in the report, and queue it for the owner |
| Usage cannot be read | Stop. Do not guess |
