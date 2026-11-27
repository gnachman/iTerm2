---
name: swift-migration-unit
description: Run one unit of the iTerm2 Objective-C to Swift migration as its orchestrator, on the trivial, light or full path, from claim to commit, and the session's closing checks. Give a unit name (an Objective-C class, Class(Category), or file), or none to pick the next eligible unit.
argument-hint: "[unit]"
---

# Run one Swift migration unit

You are the orchestrator. This skill is the order of work; the rules are in
`docs/swift-migration/`, and where this file and they disagree, they win.
"§" means a numbered section of the file named.

## 0. Before any unit

1. Do the cold start in `orchestration.md` §1 (read `README.md`,
   `workflow.md` and `lifecycle.md` in full; usage; `git status`; lanes;
   `owner-queue.md`; `claims.md`).
2. Check that units may start (`lifecycle.md` §3; `owner-queue.md`,
   `decisions.md`) and how many this session may do. If they may not,
   stop here and say why.

## 1. Pick and assign the path

1. Unit given: use it, unless it prints reserved (`reserved.md`): then
   it is not ported, unless the owner himself named it after the
   reservation, in which case ask him. None given: resume an unparked entry in `claims.md`,
   else take the next eligible unit (`orchestration.md` §2, step 4),
   preferring a batch of eligible trivial units from
   `tmp/classify.txt` (never a row whose path is reserved), which the last successful
   `tools/swift_migration/codedb/refresh.sh` wrote (`orchestration.md` §1,
   step 4), smallest first. Before briefing any unit, follow
   `orchestration.md` §1, step 4: `refresh.sh --status` first. At night up to three
   trivial or light units with no dependency on each other may be
   authored at once, each in its own lane, commits landing one at a time;
   never wait idle on one author: gate and commit each as it returns and
   launch the next; by day one at a time (`orchestration.md` §2, step 4). Start no unit
   that cannot be committed before the closing checks must start.
2. Assign the path that
   `tools/swift_migration/qualify_unit.py UNIT --callers-thread "<answer>"`
   prints (`lifecycle.md` §3; UNIT is a class or `Class(Category)`; answer
   the callers' thread from the call sites). Trivial only when T1 to T8
   all PASS. Light only when no light condition FAILs; each MANUAL is
   settled by an agent's reading, recorded in the dossier (the tool's
   evidence line, what was read, the conclusion) and checked by the
   reviewer; a MANUAL not clearly settled in the unit's favour counts as a
   FAIL, and a FAIL is never overridden. Otherwise full. Reserved (the
   tool prints `Path: reserved`; `reserved.md`): do not port it, claim
   nothing, and pick another unit. Hot path: add it to `hot-paths.md` and
   pick another.
3. Claim it in `claims.md`: unit, path, step, date, round 1.

## 2. Trivial path (`lifecycle.md` §3, "The trivial path")

Check the budget before each subagent and each gate run, on every path
(`orchestration.md` §3 step 1; `workflow.md` §4).

1. **Lane.** `lane_clone.py acquire --purpose "<unit> author"`.
2. **Author** (agent `migration-author`), kind `port`. Give it: `README.md`
   in full; `lifecycle.md` §1 step 3 and §3; `translation-rules.md`;
   `assertions.md`; `concurrency.md` §9; `nullability.md` §6; `phase0.md`
   §9; `traps.md`; `bugs.md`; the `qualify_unit.py` output; the lane instructions. No
   dossier. It writes the tests (one per reflective entry, through the
   system's door), sees them pass against the Objective-C, breaks each
   method's body once and sees every test fail in one rebuild (break a
   body by returning a wrong value, never by crashing, and check that each
   test's failure is its own method's wrong result), snapshots,
   ports, runs `pbxproj_swap.py`, snapshots again, and returns one change
   with the unit notes for the commit message; nothing more (about 15 to
   20 minutes; `lifecycle.md` §3).
3. **One reviewer** (new), reading the author's lane, given the diff, the
   deleted Objective-C, the new Swift, the qualifying output, the snapshot
   comparison, `traps.md` and `translation-rules.md`; it compares block
   captures and observer or notification registrations with the
   Objective-C, and does not rebuild or rerun tests unless something looks
   wrong. Another round only for a blocking finding that stood.
4. **Collect** as on the light path (step 3 below), without a `test`
   patch, and, for a unit briefed while the database was behind, only
   after the database refresh has exited 0 and `qualify_unit.py UNIT`
   again prints trivial (follow `orchestration.md` §1, step 4:
   `refresh.sh --status` first). Collect nothing that touches a file the
   build or the classification reads while it says `running`
   (`orchestration.md` §6, "The code database").
5. **Gate**: `README.md` §5 (the build and the targeted tests; no whole
   suite on the trivial path). If the project-file change no longer
   applies because another unit landed, run `pbxproj_swap.py` in your
   checkout (step 3 of the light path).
6. **Commit** one `port` commit by pathspec, trailer
   `Swift-Port: <unit> kind=port`, the unit notes in the message. Mark the
   unit *landed, closing checks pending* (and, for a unit named in the
   sdef, "AppleScript comparison owed" until a day session runs it,
   `lifecycle.md` §3); release its lanes. Next unit.

## 3. Light path (`lifecycle.md` §3, "The light path")

1. **Lane.** `lane_clone.py acquire --purpose "<unit> author"`.
2. **Author** (agent `migration-author`). Give it: the unit, kinds `test`
   then `port`; `README.md` in full; `lifecycle.md` §1 steps 3 and 5, and
   §3; `translation-rules.md`; `assertions.md`; `nullability.md` §6;
   `concurrency.md` §9; `phase0.md` §6 and §9; `traps.md`; `bugs.md`; the
   qualifying output; the lane instructions from the header of
   `tools/swift_migration/lane_clone.py` with `LANE` filled in. It writes
   the short dossier, settling each MANUAL of the qualifying output in
   it, and the tests, sees them pass against the Objective-C, saves the
   `test` change as a patch, then ports, running `pbxproj_swap.py` in its
   lane.
3. **Collect**: `collect N`, read it, and copy the author's saved `test`
   patch into your own `tmp/` before any release. If no other port landed
   since the lane's base (compare the base in `LANES/state/lane-N.json`
   with HEAD), then `collect N --to-index --allow-project` after reading
   the project diff. If one did, do not take the lane's project file:
   apply the `collect N` patch without it
   (`git apply --index --3way --exclude=iTerm2.xcodeproj/project.pbxproj`)
   and run `pbxproj_swap.py` in your checkout instead; stage the project
   file either way before the gate. Keep the
   author's lane until the review is over if it may be needed again.
4. **Reviewer** (agent `migration-reviewer`, new every round), in a lane
   acquired with `--apply-staged <unit paths>` (the project file is one
   of the unit's paths, here and at the gate). Give it: `README.md` in
   full; `lifecycle.md` §1 step 6 and §3; `translation-rules.md`;
   `traps.md`; the dossier; the diff; the deleted Objective-C; the new
   Swift; the snapshot comparison, the comparison of the generated
   Objective-C declaration with the old header and the bridging-boundary
   probes (`lifecycle.md` §3, "What it keeps"; `orchestration.md` §5). It checks each MANUAL reading in the
   dossier. Never the author's reasoning or earlier rounds.
5. **Findings.** Loop as in `orchestration.md` §3 steps 5 to 7 and
   `workflow.md` §1 and §2. A finding showing the unit fails a qualifying
   condition moves it to the full path.
6. **Gate.** You run it on the staged tree, in the full-suite lane
   (`acquire --full-suite` with `--apply-staged`): `README.md` §5,
   including the plain whole suite through `whole_suite.sh` before the
   `port` commit (under the whole-suite lock, which serializes whole
   suites; a stall is exit 124).
7. **Commit** by pathspec (`orchestration.md` §3 "Build lanes", and §6):
   first the `test` commit (tests, bridging-header line, dossier added)
   from the saved patch through a temporary index, then the `port` commit:
   every remaining unit path, including the bridging header (the `test`
   commit added its line, the port removes it) and the project file, with
   the dossier deleted. Trailers
   `Swift-Port: <unit> kind=test` and `kind=port`.
8. **Release** every lane the unit held.
9. **Close**: new traps into `traps.md` and bugs into `bugs.md`
   (`lifecycle.md` §1 step 8; `orchestration.md` §3 step 10); the claim
   becomes *landed, closing checks pending*.

## 4. Full path (`lifecycle.md` §1)

Each step that commits goes through `orchestration.md` §3: record the step,
lane, author, fresh reviewer, findings, the gate (with the plain whole
suite through `whole_suite.sh`, except on a `dossier` commit), commit by
pathspec, release. Give every author and reviewer `README.md` in full,
`traps.md`, `bugs.md`, the dossier and the lane instructions, plus:

| Step and kind | Also give |
|---|---|
| 2 `dossier` | `lifecycle.md` §1 step 2; `hidden-callers.md`; `concurrency.md` §10; `objc-state.md`; `phase0.md` §2, §9, §10; `warnings.md` |
| 3 `test` | `lifecycle.md` §1 step 3; `test-speed.md` §3; `large-code.md` §2 for a function over about 150 lines |
| 4 `annotate` | `nullability.md` |
| 4 `arc` | `arc.md`; `lifetimes.md` |
| 4 `undynamic` | `hidden-callers.md` |
| 4 `explicit` | `warnings.md` |
| 4 `decxx` | `objcxx.md` |
| 5 `port` | `lifecycle.md` §1 steps 5 and 6 (§2 for a large file); `translation-rules.md`; `assertions.md`; `concurrency.md`; as the dossier shows, `objc-state.md`, `lifetimes.md`, `stored-state.md`, `interop.md`, `performance.md` |
| `fix` | `README.md` §4 and §5; the `bugs.md` entry |

Reviewers also get the tool outputs the kind requires (`orchestration.md`
§5). VM checks need the owner to start vm1: queue that and work elsewhere.
Dossier commits pass `dossier_cap.py` (`lifecycle.md` §4). **Close** as
`lifecycle.md` §1 step 8 and `orchestration.md` §3 step 10 say (the commit
deleting the dossier; the claim becomes *landed, closing checks pending*).

## 5. Stop conditions

- A qualifying condition fails during the trivial or light path: the unit
  moves to a heavier path, and the reason is recorded as `lifecycle.md` §3
  says.
- Blocking findings still standing at the round cap: split or park
  (`workflow.md` §2), then take another unit.
- A defective lint, comparison or other gate tool: `workflow.md` §2.
- Anything the owner must decide (`workflow.md` §3): add it to
  `owner-queue.md`, park what depends on it, continue elsewhere. Never wait.
- Usage at the night's cap, usage unknown, or the owner at the checkout:
  stop cleanly (`workflow.md` §4).

## 6. End of session: the closing checks

Once, after the last unit and by the time the prompt names, run the
closing checks of `lifecycle.md` §5 over everything that landed, in order,
one at a time, each under the lock with its stall watchdog:
`sanitizer_tests.sh combined --parallel` (the plain whole suite, with the
nullability and integer checks compiled in: three verdicts, tests,
nullability and integer), then `sanitizer_tests.sh thread` (never
`--parallel`); the `x86_64` build; `tools/swift_migration/codedb/refresh.sh`
(the capture, the update and the classification in one command, whose
exit status you read before anything else: nonzero is a failed check),
then the lints. Wait for one in the
background only with `suite_guard.py wait --pid PID --seconds 540` in the
foreground, never by ending the turn. Fix a failure by a new commit of the
unit or `git revert`, never a reset. Units the checks passed over leave
`claims.md`; the rest stay *landed, closing checks pending*, and the report
says which checks did not run. Put changes that belong to no unit into the session's one document commit,
with no trailer, amended while unpushed (`README.md` §5, "Where commits
go"); a new tool or a Phase 0 item is its own `tool` commit. Write the night's report
(`orchestration.md` §8). Leave the tree clean, every lane released and no
process of yours running.

## Standing limits

- Never push, fetch, rebase or merge. Commit on master, by pathspec.
- Never refresh the database by running the capture, a whole
  `codedb.py update` or `qualify_unit.py --classify` by hand:
  `refresh.sh` is the one command (it also forces the files recorded
  with parse errors once), and no file the build or the classification
  reads changes in its checkout while it runs. Forcing a single file with `codedb.py update --file PATH
  --force` by hand stays allowed when no database refresh is running.
- Never touch a submodule, another checkout, `CLAUDE.md`, a settings file
  or `tools/add_file_to_xcodeproj.rb`. Subagents never commit.
- One author lane per unit at a time; at most three unit authors at once,
  and only at night.
