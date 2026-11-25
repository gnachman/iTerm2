# Unattended workflow

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The migration runs mostly unattended. If every change waited for the owner to
review it, the work would never finish. This file says how a change is made
and reviewed without the owner, when the agents run, when they stop, and what
still reaches the owner.

## 1. The author and reviewer loop

Every migration commit, of every kind, is produced by this loop. It replaces
a single review pass.

1. **An author does the work.** The orchestrator assigns one step of a unit
   to an Opus subagent, with the dossier and the topic files that step needs
   ([README.md §1](README.md)).
2. **A reviewer reviews it.** A different Opus subagent reviews the change
   for correctness and verifies that it follows every documented procedure
   that applies to it. It produces findings.
3. **The author addresses the findings.** For a finding that claims a
   behavior difference or a bug, the author first writes a test that fails
   because of it, then fixes it. For a finding about procedure, the author
   does the missing step.
4. **Back to step 2, with a new reviewer.** The loop ends when a review
   produces no blocking findings. The orchestrator then runs the gate
   ([README.md §5](README.md)) and commits.

Rules for the loop:

- **A reviewer is never reused.** Every review, in every round, is done by a
  fresh subagent that has seen nothing of the earlier rounds: not the earlier
  findings, not the author's responses, not the author's reasoning. It judges
  the change as it now stands. A reviewer that has seen earlier rounds starts
  checking whether its findings were addressed instead of whether the change
  is right.
- **What the reviewer is given:** the dossier, the diff, the code before and
  after, `traps.md`, and the topic files for that kind of commit. For a
  `port` commit its first instruction is the one in
  [lifecycle.md §1](lifecycle.md), step 6: find a behavioral difference,
  with an input that shows it.
- **Findings are labeled.** *Blocking*: a behavior difference, a procedure
  not followed, a missing or inadequate test, a claim without its required
  evidence, a lint or snapshot that should have failed. *Non-blocking*:
  style, naming within the rules, optional improvements. Non-blocking
  findings are fixed if cheap and otherwise dropped; they never keep the loop
  running.
- **A finding that is unlikely to occur in practice is non-blocking,**
  whatever its kind. That covers a defect that only hand-edited or hostile
  input can reach, a form that does not occur in this tree, and a failure
  that needs an improbable sequence of events. The orchestrator makes that
  judgment and records each finding it lets slide in the night's report,
  with the reason. A wrong result on real code in this tree is never let
  slide.
- **Each finding says how to check it:** the input, the line, or the rule and
  the file that states it. A finding that cannot be checked is not blocking.
- **A finding the author believes is wrong** is answered with evidence,
  normally a test that passes and would fail if the finding were right. The
  author does not comply silently and does not ignore it. The orchestrator
  decides. If the finding is rejected, the dossier gains a short entry under
  "Considered and rejected" stating the claim and the evidence, so that the
  next fresh reviewer sees it as a fact about the unit. A later reviewer may
  still raise it again with new evidence.
- **A test written for a finding stays.** It is part of the unit's tests from
  then on.
- **The author is the same subagent across rounds** where that is possible,
  so that it keeps its understanding of the unit. If it has to be replaced,
  the new author works from the dossier and the current diff.

## 2. When the loop does not converge

- **The cap is four rounds.** If the fourth review still has blocking
  findings, the unit is parked, unless the reviews are converging: each has
  fewer or narrower blocking findings than the last, and none of the latest
  is a wrong result on real code in this tree. Then the orchestrator may
  run further rounds, and records each extra round in the night's report.
  A review whose blocking findings are as broad as the previous one's still
  means split or park.
- **Parking** means: the uncommitted work is saved as a patch, the working
  tree is returned to the last commit, the unit's entry in `claims.md` says
  it is parked and why, and an entry is added to `owner-queue.md` with the
  outstanding findings and the author's position on each.
- **The orchestrator then moves on to another unit.** It parks and continues;
  it never blocks on the owner. There is enough other work to keep it busy
  for a long time. It does not need the owner's permission to move to the
  next unit or class.
- A unit that will not converge is usually too large or has a wrong dossier.
  Before parking, the orchestrator considers splitting the step into smaller
  commits; if that is possible, it does so and the count starts again for
  each piece.
- The owner helps with parked units when convenient. Nothing else depends on
  when.

## 3. What reaches the owner

The orchestrator never waits for the owner. Anything that needs the owner
goes into [owner-queue.md](owner-queue.md), a committed file that lists the
items needing the owner's attention, and work continues elsewhere.

Things that require the owner before they happen:

- **A change to a rule** in these files.
- **Anything in a hot path** ([performance.md §2](performance.md)).
- **The end of Phase 0** ([plan.md §1](plan.md)).
- **Moving from one tier to the next** ([plan.md §1](plan.md)). The
  orchestrator queues the request before the current tier runs out, and
  until it is answered it keeps working on what remains in the current tier,
  on giant-class extractions, and on parked units that have been answered.
- **Deleting or weakening a test, or disabling one** for any reason other
  than being flaky ([test-speed.md §3](test-speed.md)).
- **Reverting a port that has dependents.**
- **Pushing.** Agents never push (section 5).
- **Starting vm1.** vm1 is assigned to the migration and may be used for
  hands-on QA without asking which VM to use. It is not left running, so
  when VM work is ready the orchestrator asks the owner to start it. A unit
  that needs VM QA is taken up to that step and queued until vm1 is running.

Things that do not require the owner: choosing the next unit, moving from one
class to the next, starting or continuing the extractions from a giant class,
moving a test to the slow tier, disabling a flaky test (which is then
reported to the owner), parking a unit, and every ordinary commit that
passes the loop and the gate.

Each entry in `owner-queue.md` has the date, the unit, what is needed, and
what the orchestrator did in the meantime. The owner removes an entry by
answering it; the orchestrator reads the queue at the start of each night.

## 4. Schedule and usage budget

**Start.** The agents begin at local midnight.

**Budget.** They stop when the owner's weekly Claude Code usage reaches the
fraction of the week that the night represents. The quota resets on Saturday
at noon, so the first midnight after a reset is Sunday's:

| Night beginning at midnight on | Work until weekly usage reaches |
|---|---|
| Sunday | 1/7 (14%) |
| Monday | 2/7 (29%) |
| Tuesday | 3/7 (43%) |
| Wednesday | 4/7 (57%) |
| Thursday | 5/7 (71%) |
| Friday | 6/7 (86%) |
| Saturday | 7/7 (100%) |

In general the cap is the number of midnights since the last reset, divided
by seven. If the reset time changes, the table follows it.

- The owner's own use during the day counts toward the same number. If usage
  is already at or above the night's cap at midnight, no work is done that
  night.
- The exception is a one-unit night, which the owner orders for a given
  date (first for the night beginning 2026-11-23, ordered 2026-11-22). The
  plist sets `NIGHTLY_ONE_UNIT_DATE=YYYY-MM-DD`. On that local date only,
  `nightly_start.sh` starts even when usage is at or over the cap, and the
  prompt tells the orchestrator to do exactly one unit (resume the unparked
  claimed unit, else take the next eligible one), start no second, stop
  cleanly and write the report; usage at or over the cap is not a reason to
  stop that night, but unknown usage still is, before the start and during
  the night. On any other date the setting does nothing, so it expires by
  itself; an empty value means unset and a malformed one refuses the night
  (exit 64). The script's header has the details.
- Usage is checked before each subagent is started and before each gate run.
  A subagent that is already running is allowed to finish, so the overshoot
  is bounded by one subagent's work.
- Work also stops when the owner starts using the checkout in the morning,
  whatever the budget says.

**Closing checks before the stop.** The whole suites (the plain one
again, after those in the gates of light and full commits), the `x86_64` build and the
lints run once at the end of the session over everything that landed ([lifecycle.md §5](lifecycle.md)), about an hour by the measurements
of 2026-11-24. The nightly prompt names the time they must start, 75
minutes before the clean stop (`nightly_start.sh`, `CLOSING_RESERVE`); no
unit starts that cannot be committed by then. A unit committed before the
closing checks pass is *landed, closing checks pending*.

**Stopping cleanly.** When the cap is reached, or at the night's clean
stop time, the orchestrator:

1. Starts nothing new and lets running subagents finish. A background
   job that has not finished (a suite run, a build) is stopped or
   abandoned, and the report says which, and which closing checks did
   not run.
2. Commits anything that has completed the loop and passed the gate.
3. Saves any other uncommitted work as a patch and records it in
   `claims.md`, with the round the loop had reached.
4. Returns the working tree to the last commit, so that in the morning the
   tree is clean and builds.
5. Writes the night's report.

The orchestrator never waits on a background job without a bound: it
waits with `python3 tools/swift_migration/suite_guard.py wait --pid PID
--seconds 540` in the foreground and looks at the clock after each return,
instead of ending its turn to wait for the job's notification. An
interactive session idle at its prompt gets no turn until something
arrives: on 2026-11-24 the session ended its turn waiting for three suite
runs that had hung, never got another turn, missed its clean stop at 05:15
and was killed at the hard limit with no report. Since then the supervisor
also types a fixed line into the session at the clean stop, once (the
nudge, below), and the suite runs themselves have time bounds
([orchestration.md §3](orchestration.md)).

Every stop is resumable by a new orchestrator with no memory of the night:
`claims.md`, the commit trailers, the saved patches, and `owner-queue.md`
are enough.

**Mechanism.** The pieces were built in Phase 0 and dry-run on
2026-11-22, when the owner allowed the nights to start (decisions.md); the
first unattended night is the one-unit night of 2026-11-23. Until several
nights have run, treat the mechanism as unproven.

- *Reading usage.* Running `claude /usage` from a shell prints the figures as
  text, without an interactive session. The owner confirmed this on
  2026-11-18; the output included:

  ```
  Current week (all models): 20% used · resets Nov 21 at 12pm (America/Los_Angeles)
  Current week (Fable): 15% used · resets Nov 21 at 12pm (America/Los_Angeles)
  ```

  The orchestrator runs that command and reads the percentage and the reset
  time from the "all models" line. The budget in the table applies to that
  line. The reset time is read from the same line, so the table is computed
  from it and not hard-coded. This is text meant for people, not a stable
  interface: if the line is missing or does not parse, the orchestrator
  treats usage as unknown and stops. `tools/swift_migration/usage_check.py
  --run` does this: exit status 0 means another agent may start, 1 that
  usage is at or above tonight's ceiling, and 2 that usage is unknown.
- *Per-model lines.* The whole run uses Opus, for the orchestrator as well as
  the author and reviewer subagents. Lines for other models, such as the
  Fable line above, are not relevant and are ignored. Only the "all models"
  line governs.
- *Starting at midnight.* The night runs in a separate clone of the owner's
  checkout, never in the checkout itself (decisions.md, 2026-11-20). The
  owner makes the clone once by hand with
  `tools/swift_migration/nightly_clone.sh setup`; its only remote is a
  read-only bare mirror of the project's `origin/master`, so nothing in it
  can push to his repository or to GitHub through its own configuration.
  The clone's master starts as his local master, so commits of his that
  are not on GitHub yet start in the clone as its own; `setup` prints how
  far his master is ahead of and behind his `origin/master`, and he
  rebases and pushes first. The owner also
  accepts Claude Code's workspace trust dialog for the clone once by hand,
  since nobody is there at night to answer it. A launchd user agent, from
  the template `com.googlecode.iterm2.swift-migration-nightly.plist`, runs
  `tools/swift_migration/nightly_start.sh` at local midnight. Before each
  night it runs `nightly_clone.sh refresh` (section 5), which fetches the
  project's `origin/master` from GitHub over https and brings the clone up
  to it: fast-forward, keep the clone's commits when it is strictly ahead,
  reset when everything they change is already upstream, otherwise rebase
  them onto it, and refuse the night only when the rebase fails or the
  upstream was force-pushed. The upstream is GitHub, not the owner's
  checkout, because porting stale code is pointless (the owner,
  2026-11-20). Only that trusted script fetches from GitHub; a push by
  the session is stopped or reported as below. The session is not headless: it is an ordinary
  interactive `claude` session in tmux on a private socket, in the clone,
  under `tools/swift_migration/deadline_run.py`, which ends it by a hard
  time limit and kills everything it started. The owner can attach to watch
  or intervene. Git in the session may use local-path and `file://`
  transports, as in the owner's own shell (the owner, 2026-11-23: “I
  don't understand why the nightly session can't clone. That is a
  senseless rule.”), so it can clone and fetch from a local repository,
  and Xcode resolves Swift packages in the clone and the lanes as it does
  anywhere else (SwiftPM makes each package's working copy with a local
  `git clone`); nothing needs to be copied into DerivedData. A push to
  any URL, to a path whose first character is `/` or `.`, or to origin still fails.
  What the session can now do to the owner's checkout by local path,
  with no environment guard against it: push through a remote with an
  explicit pushurl, through `git send-pack`, or to a relative path whose
  first character is neither, from any directory (from the clone,
  `tmp/../../<his checkout>`), which the deny rules catch in their plain
  forms; and fetch or pull into his checkout from the clone or a lane
  (`git -C <his checkout> pull --ff-only <clone> master` moves his
  checked-out branch and changes his working tree), which no deny rule
  matches, so only the classifier reviews it. The owner-refs comparison
  below reports any ref change from these routes; working tree changes
  are not compared. The orchestrator is
  told to have stopped cleanly 45 minutes before the hard limit; the stop
  sequence starts early enough to end by the hard limit. At the clean stop
  `deadline_run.py --nudge-text` types one fixed line into the session,
  then presses Enter as a separate tmux call a second later, once each,
  bounded, logged and never retried: “It is the clean stop time. Stop now
  as docs/swift-migration/workflow.md section 4 says: start nothing new,
  stop or abandon background jobs that have not finished, commit what
  passed, write the night's report, release lanes, then stop.” Observed
  with Claude Code 2.1.331 in a private tmux server on 2026-11-24: idle at
  its prompt, the session took the line as a message and started a turn;
  typed during a turn, the line was shown as “Queued” and delivered when
  the turn ended; the same line with Enter in one tmux call was taken for
  a paste and stayed unsubmitted in the input, so the Enter goes
  separately. The stop sequence clears the input line with Ctrl-C before
  it types /exit (text left in the input would otherwise have /exit
  appended and go as a message): with leftover text, with an empty input
  (one Ctrl-C there only shows a hint) and during a turn, the session
  exited. An open dialog takes the nudge as its answer and the nudge is
  lost (observed with AskUserQuestion), so the session runs without
  AskUserQuestion; any other dialog open at the clean stop would still
  take it. For the scheduled
  midnight start the six-hour limit comes first: clean stop 05:15, hard
  limit 06:00. The 07:00 limit applies only to a later start (then 06:15
  and 07:00). After the session the script compares the refs of the
  owner's repositories with a record taken before it and lists any that
  moved in the morning log; this is a report, not a stop, since his other
  agents and worktrees share the repository. The headers of the three scripts say what each checks, how
  the session's permissions are restricted, and what a misbehaving session
  could still do. Nothing is installed.
- *Build lanes.* The nightly orchestrator uses build lanes as the daytime
  one does ([orchestration.md §3](orchestration.md); decisions.md,
  2026-11-20). The nightly clone's lanes live in `<clone>.lanes/`, beside
  the clone and outside it. `nightly_start.sh` creates that directory with
  mode 0700 and starts the session with `--add-dir <clone>.lanes`, so the
  session is allowed to edit there without a prompt, as in the clone.
  Lanes are `git worktree add` checkouts whose submodules borrow objects
  through alternates, so they need no git transport. Each lane registers
  itself in the clone's `.git/worktrees/`, in the one shape that
  `nightly_clone.sh check` allows there. After the refresh and before the
  session, `nightly_start.sh` logs `lane_clone.py status` and runs
  `release --stale`, which frees lanes left held by an earlier night and
  saves their uncollected work under `<clone>.lanes/saved/`.
- *Models.* The nightly session is started on Opus. A subagent's model is set
  by the `model` parameter when it is started, or by `model:` in an agent
  definition. The author and the reviewer have agent definitions,
  `.claude/agents/migration-author.md` and
  `migration-reviewer.md`, which pin Opus and name the files to read.
  `.claude/agents/` is tracked in git (the rest of `.claude/` is ignored),
  so the clone has them and Claude Code loads them from there; nothing is
  passed on the command line. `tools/swift_migration/agents_json.py` only
  checks, before each night, that they parse and pin Opus.
- *A hard stop.* `claude --help` on this machine lists no limit on turns.
  It has `--max-budget-usd`, a limit on dollars spent on API calls that
  works only with `--print`. The hard stop is a time limit:
  `tools/swift_migration/deadline_run.py` ends the run at a deadline and
  then kills every process the run started.

Until the usage reading has been proven over several nights, the run is also
capped by a conservative limit on its own length, so that a failure to read
usage cannot spend the week's quota.

## 5. Commits, pushing, and the morning review

- **Agents commit locally on master and never push.** At night that is
  the clone's master (section 4). In the morning the owner reviews the
  night's work, takes it into his checkout, and pushes.
- **Before each night** `nightly_clone.sh refresh`, run by
  `nightly_start.sh` and not by the orchestrator, fetches `master` from the
  URL the owner's checkout names as `origin` (https only: an ssh form is
  fetched as its https equivalent; no credentials) into the clone's
  read-only mirror. The fetched commit must be a fast-forward of what the
  mirror had: if it is not, someone force-pushed, and the night is refused.
  If GitHub cannot be reached, the night goes on with the mirror as it was
  and the run's `refresh.status` says so. Then, against that
  `origin/master`: the clone fast-forwards when it has no commits of its
  own; keeps its commits when it is strictly ahead (they are not pushed
  yet); resets to `origin/master`, saving its old master under
  `refs/nightly-saved/`, when everything its commits change is already
  upstream (the owner pushed them, perhaps squashed or reworded);
  otherwise rebases its own commits onto `origin/master`, dropping those
  already upstream as equivalent patches and those that become empty,
  keeping authors and author dates, never making a merge commit. The
  rebase is all or nothing: on a conflict, a merge commit or a commit that
  moves a submodule pointer, the clone is left exactly as it was, its old
  master is kept under `refs/nightly/pre-rebase/`, the log names the
  commit and the files, and the night does not start (exit 9). Submodule
  commits the new code records and no local repository has are fetched
  from the submodule's https URL in `.gitmodules`; one that cannot be is
  left at its old commit, loudly. The orchestrator never fetches, rebases
  or merges.
- **The owner takes the night's commits** with the fetch and fast-forward
  command that `nightly_start.sh` prints, which does nothing unless his
  checkout has master checked out, reviews them, and pushes. If the
  fast-forward refuses because his master has commits the clone does not
  (his own unpushed commits, or an earlier night's commits he took and did
  not push), he runs the printed `git rebase FETCH_HEAD` after the same
  fetch: it replays his own commits on top of the night's work and drops
  those already in it as equivalent patches. A cherry-pick of
  `master..FETCH_HEAD` would be wrong, since that range also holds
  upstream commits his master lacks.
- **If the owner does not push on some day**, the clone keeps its commits
  and rebases them onto the new `origin/master` the next night. Nothing
  waits for him.
- **If a rebase fails**, the night is skipped; the log says which commit
  conflicted, in which files, and how to rebase the clone by hand or set
  its commits aside with `nightly_clone.sh reset`.
- **Before the first night** the owner's own unpushed commits must be on
  GitHub, or the clone carries them as its own and rebases them every
  night until they are. `setup` names any of them that change a rule file
  (CLAUDE.md, CLAUDE.local.md, `.claude/`, `.mcp.json`): until those are
  on GitHub every night is refused.
- **After a force-push upstream** the night is refused;
  `nightly_clone.sh reset --accept-rewritten-upstream` takes the rewritten
  master, keeping the old one under `refs/nightly/rewritten/` in the
  mirror.
- **The night's report** is for the morning review. It lists, from the
  commit trailers, each unit touched with its commits and kinds; how many
  review rounds each took; findings that were rejected, with the evidence;
  anything parked; each closing check with its result, duration and run
  directory, and the units still *landed, closing checks pending*; new entries in `owner-queue.md`, `bugs.md` and
  `traps.md`; the usage at the start and end; and why the run stopped. It is
  written to `tmp/` and is not committed, since everything in it that
  matters is also in the repository.
- **If the owner rejects a commit in the morning**, it is reverted or
  dropped before the push, the reason goes into `decisions.md` or
  `traps.md` as appropriate, and the unit returns to the queue. Because each
  commit stands alone, dropping one does not disturb the others unless they
  build on it.

## 6. What makes this safe without the owner

The owner's review is replaced by layers that do not depend on anyone's
attention:

- The loop, with a fresh reviewer every round.
- The gate, including the snapshot comparisons and lints, which are
  mechanical and cannot be argued with.
- The morning review before anything leaves the machine.
- Crash reports and beta assertion failures from nightly and beta builds,
  attributed by line when they arrive. Nothing waits for them
  ([lifecycle.md §1](lifecycle.md), step 7).
- Every commit being revertable alone.

The pilot is where this is tested. Its results, including how many real
defects the loop caught and how many it missed, are in front of the owner
before the agents are run at scale.
