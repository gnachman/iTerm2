---
name: swift-migration-unit
description: Run one unit of the iTerm2 Objective-C to Swift migration as its orchestrator, on the light or the full path, from claim to commit. Give a unit name (an Objective-C class or file), or none to pick the next eligible unit.
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
2. After the two pilot units no unit starts until the owner says so
   (`lifecycle.md` §3; `owner-queue.md`, `decisions.md`). If he has not,
   stop here and say why.

## 1. Pick and assign the path

1. Unit given: use it. None given: resume an unparked entry in `claims.md`,
   else take the next eligible unit (`orchestration.md` §2, step 4).
2. Assign the path as `lifecycle.md` §3 says. Answer the callers' thread
   from the call sites and run
   `tools/swift_migration/qualify_unit.py CLASS --callers-thread "<answer>"`.
   The light path only when no condition prints FAIL. Each MANUAL is
   settled by an agent's reading, recorded in the dossier (the tool's
   evidence line, what was read, the conclusion) and checked by the
   reviewer; a MANUAL not clearly settled in the unit's favour counts as a
   FAIL, and a FAIL is never overridden. Otherwise the full path. Hot
   path: add it to `hot-paths.md` and pick another.
3. Claim it in `claims.md`: unit, path, step, date, round 1.

## 2. Light path (`lifecycle.md` §3)

Check the budget before each subagent and each gate run
(`orchestration.md` §3 step 1; `workflow.md` §4).

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
   Objective-C declaration with the old header, the bridging-boundary
   probes and the lint output (`lifecycle.md` §3, "What the light path
   keeps"; `orchestration.md` §5). It checks each MANUAL reading in the
   dossier. Never the author's reasoning or earlier rounds.
5. **Findings.** Loop as in `orchestration.md` §3 steps 5 to 7 and
   `workflow.md` §1 and §2. A finding showing the unit fails a qualifying
   condition moves it to the full path.
6. **Gate.** You run it on the staged tree, in the full-suite lane
   (`acquire --full-suite` with `--apply-staged`): `README.md` §5 steps 1
   to 6 and the whole suite, once per port, before committing.
7. **Commit** by pathspec (`orchestration.md` §3 "Build lanes", and §6):
   first the `test` commit (tests, bridging-header line, dossier added)
   from the saved patch through a temporary index, then the `port` commit:
   every remaining unit path, including the bridging header (the `test`
   commit added its line, the port removes it) and the project file, with
   the dossier deleted. Trailers
   `Swift-Port: <unit> kind=test` and `kind=port`.
8. **Release** every lane the unit held.
9. **After committing** (one pass may cover several units): recapture,
   `codedb.py update --accept-removals`, and the lints that need a
   capture (`phase0.md` §6, "Where they run"). A finding goes back to the
   author; its fix is a new commit of the unit.
10. **Close**: new traps into `traps.md` and bugs into `bugs.md`
   (`lifecycle.md` §1 step 8; `orchestration.md` §3 step 10), then remove
   the claim.

## 3. Full path (`lifecycle.md` §1)

Each step that commits goes through `orchestration.md` §3: record the step,
lane, author, fresh reviewer, findings, gate steps 1 to 6, commit by
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
**Close** as `lifecycle.md` §1 step 8 and `orchestration.md` §3 step 10
say (gate steps 7 and 8, the commit deleting the dossier, the claim
removed).

## 4. Stop conditions

- A qualifying condition fails during the light path: the unit moves to
  the full path, and the reason is recorded as `lifecycle.md` §3 says.
- Blocking findings still standing at the round cap: split or park
  (`workflow.md` §2), then take another unit.
- Anything the owner must decide (`workflow.md` §3): add it to
  `owner-queue.md`, park what depends on it, continue elsewhere. Never wait.
- Usage at the night's cap, usage unknown, or the owner at the checkout:
  stop cleanly (`workflow.md` §4).

## 5. End of session

Run the thread sanitizer suite and the x86_64 build over the light ports
that landed (`lifecycle.md` §3); fix a failure by a new commit or
`git revert`, never a reset; list uncovered ports in the report. Put changes that belong to no unit into the session's one document commit,
with no trailer, amended while unpushed (`README.md` §5, "Where commits
go"); a new tool or a Phase 0 item is its own `tool` commit. Write the night's report
(`orchestration.md` §8). Leave the tree clean, every lane released and no
process of yours running.

## Standing limits

- Never push, fetch, rebase or merge. Commit on master, by pathspec.
- Never touch a submodule, another checkout, `CLAUDE.md`, a settings file
  or `tools/add_file_to_xcodeproj.rb`. Subagents never commit.
- One author lane per unit at a time.
