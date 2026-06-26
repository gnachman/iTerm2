# Window Projects / Cold Storage — Design Notes & Understanding

Status as of 2026-06-23. This is the living reference for the feature. It captures
the architecture we reverse-engineered, what we built, what's verified, the open
design questions, the planned UI, the test matrix (and what's automatable), the
cleanup inventory, and a dogfooding assessment. Intended to let future focused
sessions (GUI, close-semantics, persistence, tests, cleanup) start cold.

---

## 1. Goal

Stash/archive groups of windows. Restore either:
- **just the terminal state** (layout, geometry, unlimited scrollback), or
- **optionally keep the processes running** under iTermServer and *reattach* the
  restored window's GUI to the still-running shell instead of spawning a new one.

The original blocker (now solved): in-process freeze→thaw could keep the process
alive but could not reattach on restore.

---

## 2. Window state model

Three (arguably four) states:

- **open (associated)** — live window that belongs to a project.
- **detached** — frozen; process still running under iTermServer; arrangement +
  scrollback saved; GUI reattaches on restore.
- **closed (archived)** — frozen; process gone; only layout + scrollback saved.
- *(unassociated open — a live window not in any project. Possible future idea:
  treat these as members of a catch-all "null" project.)*

Naming is provisional — user dislikes "freeze". Likely rename to
**Archive & Close** vs **Archive & Detach**, with states open/closed/detached.
See `memory/window-projects-naming-direction`.

---

## 3. Architecture: how iTerm session restoration actually works

The hard-won understanding. These are the load-bearing facts.

### Multiserver / iTermServer
- Each running iTerm instance has **one shared multiserver daemon** (socket file
  `~/Library/Application Support/iTerm2/iterm2-daemon-N.socket`). Prod and a
  side-by-side dev build get different sockets (e.g. prod=1, dev=2). One daemon
  hosts **many** children (all the normal sessions). The daemon owns the real PTY
  master fds, which is why children survive the client (iTerm) quitting/crashing.

### The attach precondition (the crux)
- `iTermMultiServerConnection.attachToProcessID:` succeeds **only if the child PID
  is in that connection's `unattachedChildren` list** (`iTermMultiServerConnection.m`).
- `unattachedChildren` is populated **only by the handshake** that happens when a
  connection is first established (`iTermFileDescriptorMultiClient` → `didDiscoverChild`).
  When a child is attached, it's *removed* from that list.
- Therefore: at **app startup**, the connection is brand-new → handshake
  re-discovers every orphan → attach works (this is the "bare recovered tabs"
  behavior). **In-process**, the daemon connection is already cached and shared
  and never re-handshakes, so an orphaned child is NOT in `unattachedChildren` →
  attach fails → restore falls back to a fresh shell.

### Restore paths
- `PseudoTerminal(arrangement:)` → `restoreArrangement` (sync, partialAttachments:nil)
  → `sessionFromArrangement` (`PTYSession.m`) → if `runJobsInServers` and the
  arrangement has a `Server Dict` → `tryToAttachToMultiserverWithRestorationIdentifier:`.
- If attach fails, `sessionFromArrangement` does NOT abort: `runCommand` stays YES
  and it relaunches a **fresh shell** while still restoring saved scrollback
  contents + working directory. → graceful fallback for the reboot/process-lost case.
- The async path (`openPartialAttachmentsForArrangement` → `loadArrangement` with
  partialAttachments) is what macOS window restoration uses; it has the same
  attach precondition.

### Startup orphan adoption
- `iTermOrphanServerAdopter` runs after window restoration completes
  (`iTermApplicationDelegate.m`, post-restoration block). It establishes a fresh
  connection per daemon socket (handshake → unattachedChildren) and opens a
  generic "recovered" window for every leftover orphan not already claimed by
  macOS restoration.

### The `Archive` arrangement key — NOT what it seemed
- `TERMINAL_ARRANGEMENT_ARCHIVE` / `PTYSessionArrangementOptionsArchive` only
  affect window sizing + banners on restore. They do **not** trigger reattachment.
  (Gemini's docs claimed otherwise; that was a wrong lead. Reattach is gated by
  `runJobsInServers` + presence of `Server Dict`, both already satisfied by our
  capture.)

---

## 4. What we built

All on branch `windowprojects`.

### In-process freeze→thaw reattach (VERIFIED)
- **Park instead of close-fd.** On freeze-with-keep-jobs, hand the live child back
  to its connection's `unattachedChildren` *without closing the fd* and without
  tearing down the shared connection. Native thaw attach then re-adopts it.
  - `iTermMultiServerConnection.reinsertUnattachedChild:` (re-adds child on the
    connection thread).
  - `iTermMultiServerJobManager.parkChildForReattachment` (moves `state.child` →
    connection unattached, nils child/cachedChild *without* `closeFileDescriptor`).
  - `PTYTask.parkChildForReattachment` (deregisters from TaskNotifier, keeps fd).
  - `iTermWindowProjectsModel.parkSessionsForReattachment` — shared helper called
    from BOTH `archiveWindow` and `closeProject` (the "Freeze All" button routes
    through `closeProject`, which is easy to miss — it was the bug in the first
    attempt).
- **Why not tear down the connection** (Gemini's `purgeCachedConnection`): the
  daemon connection is shared by every live session, so closing it corrupts the
  others. Parking touches only the one child.

### Cross-restart: orphan adopter claim-list (VERIFIED)
- `iTermWindowProjectsModel.claimedMultiserverChildPIDs()` returns every Child PID
  across archived arrangements (via `allServerChildPIDs(in:)`).
- `iTermOrphanServerAdopter.claimedChildPIDsProvider` (block) is wired in the app
  delegate; the adopter **skips** claimed children, leaving them parked so an
  on-demand project restore reattaches them instead of a stray recovered tab.

### Open associated windows: persist by GUID (Option A — built, NOT yet tested)
- `liveAssociations` re-keyed from window-number → stable `terminalGuid`, and
  persisted to a separate `WindowProjectAssociations.json` (projects JSON
  untouched). Restored windows keep their guid, so `project(for:)` re-resolves
  them after a restart with no fragile reconcile step.
- `applicationWillTerminate` no longer archives open windows (that produced a live
  restored window + a stale archive duplicate); it just sets `isTerminating` so
  the willClose notifications during teardown are ignored (associations preserved).
- `windowWillClose` still archives a *user-initiated* close (the "closed" state),
  keyed by guid.

### Diagnostics (temporary)
- `/tmp/iterm_wp.log` via `iTermWindowProjectsModel.wpLog`: `FREEZE park …`,
  `THAW before/after restore …` (childPresent, reattached), `claimedMultiserverChildPIDs …`,
  `loadAssociations …`.
- `ITERM_WP_PARK=0` env var disables parking (reproduces the pre-fix failure).
- `tools/claude_script_0001_inspect_arrangements.py` decodes WindowProjects.json.
- `tools/claude_script_0002_run_dev_thaw_test.sh` launches dev + tails the log.

---

## 5. Verified vs unverified

| Behavior | Status |
|---|---|
| In-process freeze→thaw reattaches same PID; blocked terminal | ✅ verified (pid match + negative control) |
| Parking is causal (ITERM_WP_PARK=0 → fresh shell) | ✅ verified |
| Detach → quit/relaunch → adopter skips claimed → restore reattaches | ✅ verified (pid match) |
| Open+associated across normal restart re-associates, no dup (Option A) | ⏳ built, untested (#5) |
| Crash (no applicationWillTerminate) consistent with clean quit | ⏳ untested (#6) |
| Process-lost/reboot → graceful fresh shell + scrollback | ⏳ untested (#4) |
| Multi-pane: all children parked/reattached | ⏳ untested (#7) |
| No regression to other live sessions on shared daemon | ⏳ untested (#8) |
| Direct-close of associated window semantics | ⏳ untested (#9) |

---

## 6. Open design questions (captured, not decided)

### 6a. Point-in-time snapshot vs live backing
Currently archives are **point-in-time** (arrangement captured at freeze). Ideas:
- **Live text teeing**: reuse the Session → Log → "Log to File" path
  (`iTermLoggingHelper`) to continuously tee terminal output into the project's
  archive. Assessment: *lightweight for raw text*, but scrollback restore uses
  full line-buffer dictionaries (colors/attributes/wrapping), not plain text — so
  text teeing alone wouldn't give fidelity restore. Full-state live streaming is
  heavy.
- **Periodic re-snapshot**: re-capture the arrangement every N minutes / on
  activity to bound staleness without streaming. Much cheaper; probably the
  pragmatic middle ground.
- Conceptual question to settle: are archives a *point-in-time save* or an
  *up-to-date backing*? The whole point (preserving scrollback larger than macOS
  recovery keeps) leans toward "backing", which argues for periodic re-snapshot or
  teeing.

### 6b. Crash merge (macOS recovery ⊕ window-projects)
After a crash, macOS recovery may hold a *recent but truncated* buffer while the
project holds an *older but longer* one. Merge = find the seam (longest common
run / suffix-of-archive vs prefix-of-recovery) and concatenate. Assessment:
**medium difficulty, fragile** (cleared logs, wrapping, timestamps, ANSI).
Likely not worth it initially; prefer "take the longer one" or periodic
re-snapshot. With **Option A**, open windows aren't archived on quit, so the
duplicate/merge problem mostly disappears for the clean-quit case.

### 6c. Closing a single associated window — what should happen?
Options the user raised:
1. close + **delete** the saved window (close = "done with it")
2. close + **update** the saved snapshot (close = "for now; keep it fresh")
3. close + **neither** (close=close, saved=saved; simplest, least clear)
4. **ask** (dialog with "don't ask again") backed by a 4-way setting (the three
   above + "ask")
5. or add/replace an option with **detach**
Current behavior = (2)-ish: `windowWillClose` archives a snapshot on user close.
**DECIDED & BUILT (2026-06-25).** Shipped option (4)-as-a-dialog, but reduced to
the outcomes the current *move*-model actually distinguishes (a live associated
window has no coexisting snapshot — restore consumes the archive — so "leave
stale" vs "delete" collapse; deferred to the §6a backing-model work). The dialog
(`iTermWarning`, permanently-silenceable, identifier
`NoSyncWindowProjectCloseAction`) offers four actions, default = **Save & Detach**:
- **Save & Detach** → `archiveWindow(close:true, keepJobsRunning:true)` (snapshot + park, keeps jobs)
- **Save & Close** → `archiveWindow(close:true, keepJobsRunning:false)` (snapshot, ends process)
- **Remove from Project** (destructive) → `disassociateWindow` + close, no snapshot
- **Cancel** (never remembered → window can't become unclosable)

Routing: `iTermWindowProjectsModel.handleUserInitiatedClose(of:)` →
`iTermWindowProjectCloseHandling` (notAssociated / handled / cancelled), called
from `PseudoTerminal.windowShouldClose:` (the cancelable hook — `willClose` is too
late, see §13a). The chosen action runs on the next runloop tick (avoids
re-entering close from within `windowShouldClose:`); it removes the association
first, so the model's `windowWillClose` fallback no-ops (no double archive). The
"Remember my choice" checkbox IS the don't-ask-again config (per-selection,
NSUserDefaults). **NOT exposed in Settings UI** — promote to a
`kPreferenceKeyWindowProjectCloseBehavior` enum if/when that's wanted.

### 6d. Exit behavior
Parallel to 6c, but for app quit. Options include: save+close, save+detach, or
save + set an **auto-restore-on-next-launch** flag so open-on-exit windows
reopen from archives at startup. Note the symmetry: whether or not the user has
macOS "reopen windows on relaunch" enabled changes the default outcome:
- recovery OFF → default is "keep a saved-but-stale version" (point-in-time)
- recovery ON → macOS reopens the live window; with Option A there's no archive
  duplicate (we stopped archiving open windows on quit). Staleness is no worse
  than normal (we don't live-stream).

### 6e. Catch-all "null" project
Possibly auto-associate *all* unassociated windows with a hidden catch-all project
so everything benefits from cold-storage/unlimited-scrollback backing. Big change
to the model; flagged as future, opt-in.

### 6f. Scope/architecture caution
Pulling unassociated windows into projects, and "wresting control" from macOS
session restoration, are both large changes to iTerm's core model. Prefer a
circumscribed feature/PR that doesn't alter the core model unless the user opts
in. Parking + claim-list + guid-association (what we built) are deliberately
contained; the live-backing/catch-all ideas are not.

---

## 7. UI / UX plan (drag overlays, panes, buttons)

Gemini attempted this and kept making mistakes; the *intent* is sound:

- **Drag right→left (unassociated window) onto a project** → associate.
- **Drag right→left (associated window/project)** → show two overlays **Close**
  and **Detach**; do NOT associate onto rows.
- **Drag left→right (window/project)** → overlay **Open**; on drop, open them.
- Consider a **split right pane**: separate areas for *detached* and *open* (and
  maybe *closed*); dragging between areas shows the matching overlay. If fully
  split, every associated window appears in the left pane and one right sub-pane,
  and dragging to a project ONLY associates.
- Need an explicit way to **disassociate** a window and/or **delete** a saved
  window (currently missing).
- **One** Open button (no separate Open/Open All). Do not allow "open ALL" with
  nothing selected (slowdown risk) unless behind a confirm dialog.
- **Multi-select** on any pane; buttons apply to selection. Buttons must work for
  both windows and projects.
- Possibly **save/load a project to/from a file** (then decide dedup/merge/
  take-newest, or accept duplicates, or ask).

A GUI-focused session needs §3–§4 understanding of how the code works, but not
the close/exit-semantics deliberation.

---

## 8. Test catalog (explained)

Each test spelled out: what it proves, setup, steps, pass criteria, how to
observe, automatability, status. "Integration" = AppleScript E2E like
`tools/recreate_cold_storage_state.sh` driving a live dev build. "Manual" =
can't be reliably automated; follow the written procedure. Use a UNIQUE marker
per run (e.g. `/bin/sleep <rand>`) so old orphans don't confuse you.

Use `tools/claude_script_0002_run_dev_thaw_test.sh` to launch the dev build (not
prod) and tail `/tmp/iterm_wp.log`; `claude_script_0001_inspect_arrangements.py`
to decode saved arrangements.

### #1 — In-process freeze→thaw reattach (parking ON) — ✅ VERIFIED, integration
- **Proves:** detaching a window keeps its process alive AND restoring in the
  same session reattaches the GUI to that *same* process (not a fresh shell).
- **Setup:** dev build, `ITERM_WP_PARK` unset/`1`, log cleared.
- **Steps:** open a window, run `/bin/sleep <R>`; associate to a project; "Freeze
  All" (detach); confirm window closed and `pgrep -f "sleep <R>"` alive; Restore.
- **Pass:** log shows `FREEZE park … parkedPid=<R-pid>`, `THAW before restore …
  childPresent=true`, `THAW after restore … restoredShellPid=<R-pid>
  reattached=true`; and the restored terminal is **blocked** (no fresh prompt)
  until you `kill` the sleep — the true-reattach signature.
- **Observe:** `/tmp/iterm_wp.log` + the window's behavior.

### #2 — Negative control (ITERM_WP_PARK=0) — ✅ VERIFIED, integration
- **Proves:** parking is the *cause* — without it, the same flow fails.
- **Steps:** as #1 but launch with `ITERM_WP_PARK=0`.
- **Pass:** `FREEZE park: DISABLED…`, `childPresent=false`, `reattached=false`,
  restored window is a fresh shell.

### #3 — Detach → quit/relaunch → adopter skips claimed → restore — ✅ VERIFIED, integration
- **Proves:** across a full iTerm restart, the startup orphan adopter does NOT
  steal a detached window's process into a generic recovered tab; it stays parked
  and the project restore reattaches it.
- **Steps:** detach a `/bin/sleep <R>` into a project; kill+relaunch the dev app;
  observe startup; then Restore from the project.
- **Pass:** NO generic recovered window for `<R>`; log shows
  `claimedMultiserverChildPIDs: […,<R-pid>,…]` and `Orphan adopter skipping
  claimed child pid <R-pid>`; after Restore `reattached=true` (pid match).

### #4 — Process-lost / reboot fallback — ⏳ PENDING, manual
- **Proves:** if the process is truly gone (reboot killed daemon+orphan), restore
  degrades gracefully — you still get the window back with scrollback and a fresh
  shell, no crash.
- **Setup (simulate reboot w/o rebooting):** detach a window; then
  `kill -9` BOTH the orphan process AND its `iTermServer` daemon (stale socket).
- **Steps:** in the panel, note the row renders as **closed/dead** (grey, no
  `[Active]`) because `isOrphanedAndRunning`’s `kill(pid,0)` now fails; Restore.
- **Pass:** window reopens with restored scrollback + saved CWD, running a fresh
  shell; log `reattached=false`; no crash; the archive entry is consumed (not left
  behind as a duplicate).

### #5 — Open+associated window across NORMAL restart (Option A) — ⏳ IN PROGRESS, integration
- **Proves:** a window left *open* (not detached) and associated to a project
  comes back **live and still associated** after a clean quit — no duplicate
  archive entry, no stray recovered tab. (Relies on native window restoration
  being enabled.)
- **Setup:** ensure iTerm window restoration is ON.
- **Steps:** open a window, `/bin/sleep <R>`; associate to a project; do NOT
  freeze; note `pgrep -f "sleep <R>"`; **clean-quit** the dev app (Cmd-Q, not
  pkill); relaunch.
- **Pass:** the window returns live (same `<R>` pid if iTerm’s quit settings keep
  jobs); panel shows it under its project (re-associated), project has 0 archived
  + 1 live; no duplicate; no generic recovered tab. Log: `loadAssociations: N …`
  includes the window’s guid.
- **Note:** if window restoration is OFF, the window won’t return — documented
  limitation, not a bug.

### #6 — Crash (no applicationWillTerminate) — ⏳ PENDING, manual/flaky
- **Proves:** crash behavior is consistent with clean quit (re-associate by guid;
  no duplicate).
- **Steps:** as #5 but `kill -9` the dev app (skips applicationWillTerminate);
  relaunch.
- **Pass:** if iTerm restored the window (depends on its periodic state save), it
  is re-associated by guid and not duplicated. Inherently flaky because crash-time
  restorable-state availability isn’t guaranteed — document the observed outcome.

### #7 — Multi-session (split-pane) parks/reattaches all children — ⏳ PENDING, integration
- **Proves:** a window with multiple split panes parks AND reattaches *every*
  child, not just the first.
- **Steps:** one window, split into N panes, each running `/bin/sleep <Ri>`;
  detach; restore.
- **Pass:** `FREEZE park` logs N parked pids; `allServerChildPIDs` returns all N;
  each restored pane reattaches its own `<Ri>` (all blocked until killed).

### #8 — No regression to other live sessions on the shared daemon — ⏳ PENDING, manual
- **Proves:** parking/restoring one window does not disturb the *other* live
  sessions that share the same daemon (the whole reason we park instead of tearing
  down the connection).
- **Steps:** open 3+ live windows (shared daemon); detach+restore ONE; then
  exercise the others.
- **Pass:** the others keep working — I/O flows, they can be closed/killed
  cleanly, and they still get termination notifications (no zombie/hang).

### #9 — Direct-close (windowShouldClose) semantics — ⏳ BUILT, needs manual verify, integration
- **Proves:** closing an associated window with the red button shows the
  Save & Detach / Save & Close / Remove from Project / Cancel dialog (§6c), and
  each outcome behaves: association removed; Detach keeps the process parked &
  reattachable; Close & Remove end the process; no orphan/zombie leak; no double
  archive from the `windowWillClose` fallback; Cancel leaves everything intact.
- **Steps:** associate a live window running `/bin/sleep <R>`; click the red
  button. For each of the 4 buttons (clear the remembered choice between runs via
  the “Always Show Alerts with Remembered Selections” mode or
  `clearSavedSelectionForIdentifier:NoSyncWindowProjectCloseAction`): confirm
  Detach → `pgrep -f "sleep <R>"` alive + Restore reattaches; Close/Remove →
  process gone; Remove → no archive entry added; Save & Close → exactly one
  archive entry. Also verify “Remember my choice” suppresses the dialog next time
  and applies the same action; Cancel can’t be remembered.
- **Note:** non-user closes (last session exits, programmatic close) still go
  through the `windowWillClose` auto-archive fallback — no dialog there (correct).

### #10 — Empty 42-byte arrangement capture (BUG) — ⏳ PENDING, unit + manual repro
- **Proves/repro:** some captures produced an empty 42-byte plist (no Tabs/
  contents). Find which freeze path/timing yields an empty
  `arrangementExcludingTmuxTabs`, fix it, and add a guard that refuses to archive
  an empty arrangement.
- **Unit:** feed a known-good arrangement vs an empty dict to the
  archive/guard logic and assert the guard rejects empty.
- **Manual:** reproduce the capture condition, confirm fixed.

### #11 — Chatty process while parked (PTY backpressure) — ⏳ PENDING (decision), manual
- **Proves/decides:** while parked we hold the master fd but stop reading it, so a
  noisy orphan can block on a full kernel PTY buffer (same as native orphaning).
- **Steps:** detach a window running a chatty process (e.g. `yes` or `tail -f` of
  a growing file); wait; restore.
- **Observe:** did the process block/stall? was output lost? Decide whether
  detached windows should keep draining the fd; record the policy.

### Unit-testable logic (headless, ModernTests — no running app)
- `serverDict(in:)` / `allServerChildPIDs(in:)` — extraction from synthetic
  arrangement dicts (incl. nested split-pane Subviews).
- `claimedMultiserverChildPIDs()` — over a synthetic project tree (incl. nested
  children); asserts every archived Child PID is collected.
- Association persistence round-trip — save then load
  `WindowProjectAssociations.json`; assert guid→project survives; guid-keying and
  the isTerminating guard (refactor side effects out so they’re testable).
- `isOrphanedAndRunning` — already tested with a live PID (self) vs a fake dead PID.
- Empty-arrangement guard (#10) once added.

### E2E harness gotchas (confirmed)
- Dev + prod share the bundle id `com.googlecode.iterm2`, so
  `tell application "<path>"` can route Apple Events to the **prod** iTerm. Target
  the dev instance by **PID** via System Events instead.
- `select row N of outline 1` is ignored by `NSOutlineView`; you must
  `set selected of row N to true` to fire the selection delegate (otherwise the
  panel’s selected-project/window stay nil and buttons stay disabled).

---

## 9. Cleanup inventory (dead/experimental code)

Before shipping / PR:
- **Remove or gate the diagnostics**: `wpLog` + `/tmp/iterm_wp.log`, the
  `ITERM_WP_PARK` env toggle, `logUnattachedState`, `logRestoredAttachment`,
  `logResolvedAssociations`. Keep behind a debug flag, don't ship always-on.
- **Pathfinder**: `iTermWindowProjectsPathfinder` (`tryManualAdoption`,
  `runDiagnostics`, `dumpConnectionState`) + the "Run Pathfinder" menu items in
  `iTermProjectsPanelController` — experimental; remove or move behind a debug
  menu.
- **Cosmetic**: `FREEZE park … tty=nil` logs tty after nil-ing the child; read it
  before parking.
- **Untracked temp tools** in `tools/`: `*.bak`, `socket_client_explorer*`,
  `socket_probe.py`, `protocol_explorer.py.bak`, `recreate_cold_storage_state.sh`
  — decide which to keep (stash vs delete; `recreate_cold_storage_state.sh` is
  useful as a test fixture).
- **The wip checkpoint commit** (`79bcabf62`) preserves Gemini's reflection-based
  approach for history; the working tree no longer uses it.
- **Minor**: prune stale `liveAssociations` entries when a project is deleted
  (lookup already tolerates dangling entries, so low priority).
- **Don't commit** AI markdown (this file, handoff) per CLAUDE.md — ship code only.

---

## 10. Dogfooding assessment

**Reasonably ready to dogfood the core**, with caveats:
- ✅ In-process detach→restore reattach works and is safe to the shared daemon.
- ✅ Cross-restart detach→relaunch→restore works (claim-list).
- ⚠️ Option A (open windows re-associate across restart) is **built but untested**
  — verify #5/#6 before relying on it.
- ⚠️ Diagnostics write to `/tmp/iterm_wp.log` on every freeze/thaw (harmless, but
  noisy) and `ITERM_WP_PARK` defaults to parking ON.
- ⚠️ Known bug: some captures produce empty 42-byte arrangements (#10) — a
  detached window with an empty arrangement won't restore. Add a guard before
  trusting it for real work.
- ⚠️ Chatty detached processes can block on a full PTY buffer (#11) — fine for
  shells/sleeps, risky for `tail -f`/builds.

Recommendation: dogfood with shells/interactive sessions; avoid detaching very
chatty processes until #11 is decided; fix #10's empty-arrangement guard first.

---

## 11. Suggested session split

- **GUI session**: §3–§4 + §7. Implement drag/overlay model, panes, multi-select,
  disassociate/delete, single Open button.
- **Close/exit-semantics session**: §6c–§6d. Implement the 4-way setting + dialog.
- **Persistence/robustness session**: §6a–§6b + tests #4/#6 + #10 empty-arrangement
  guard.
- **Test-hardening session**: §8 — write the headless unit tests + stabilize the
  E2E harness.
- **Cleanup/PR session**: §9 — gate diagnostics, remove pathfinder, finalize.

---

## 12. Swift⇄ObjC bridging heuristics (read before touching the panel)

Gemini repeatedly broke the open-windows pane on `terminals` / `allSessions`.
The failure: `iTermController.sharedInstance().terminals as? [PseudoTerminal] ?? []`
— it dropped the `()` AND kept a redundant cast — which silently yields an
**empty array** (pane shows nothing, no crash, no error). Even its eventual "fix"
re-added `()` but **kept the cast**, leaving the same landmine armed.

**Reference table (check the actual header — the same selector can differ by class):**

| Call | ObjC decl | Swift type | Correct |
|---|---|---|---|
| `iTermController.terminals` | `nullable NSArray<PseudoTerminal *> *` | `[PseudoTerminal]?` | `terminals() ?? []` |
| `iTermController.allSessions` | `nullable NSArray<PTYSession *> *` | `[PTYSession]?` | `allSessions() ?? []` |
| `PseudoTerminal.allSessions` | bare `NSArray *` | `[Any]!` | `allSessions() as? [PTYSession] ?? []` |
| `iTermController.sharedInstance` | `iTermController*` (no nullability) | `iTermController!` | `.sharedInstance()` |

**Rules:**
1. **Method vs property.** Only ObjC `@property` bridges to a Swift property. A
   plain `- (T)foo;` is a Swift **method `foo()` — needs parens**, even zero-arg
   getter-looking ones (`terminals`, `allSessions`, `currentSession`). No parens =
   a function *reference*, not a call.
2. **Cast only when the ObjC return is a bare `NSArray *`.** Typed
   `NSArray<Foo *> *` → `[Foo]?` (no cast). Decide per declaration, not by habit.
3. **Never add a redundant `as?`.** On an already-typed value it does nothing
   *except* turn would-be compile errors (missing `()`, wrong element type) into a
   silent `nil`/`[]`. Write the narrowest expression: `thing() ?? []`. Let the
   compiler be the guardrail.
4. **Nullability:** `nullable` → optional → `?? []`. Unannotated (e.g.
   `sharedInstance`) → IUO; call directly or `?.`.

Rule of thumb: **`thing() ?? []`** for typed collections; add `as? [Foo]` ONLY
when the header says bare `NSArray`. Any `as?` on an already-typed value is a
smell — delete it.

---

## 13. Close/Exit semantics — implementation reference (for the §6c/§6d session)

Researched 2026-06-25. The exact code map for adding a confirmation dialog when an
associated window is closed, and the analogue for app quit.

### 13a. THE LOAD-BEARING GOTCHA: `willClose` is too late to Cancel
The current archive-on-close logic lives in `iTermWindowProjectsModel.windowWillClose(_:)`
(observer on `NSWindow.willCloseNotification`, registered in `init`, model.swift
~264–273, handler ~461–490). **`willCloseNotification` fires after the close
decision is already made — you cannot veto it.** So a dialog with a **Cancel**
button CANNOT be driven from there.

The cancelable hook is **`PseudoTerminal.windowShouldClose:`** (`PseudoTerminal.m:4189`),
which returns `BOOL` and is only called on *user-initiated* close (red button /
Cmd-W), not on a session dying. It already centralizes close-prompting:
`needPrompt` → `showCloseWindow` (the running-jobs prompt) and the tmux 4-button
dialog via `killOrHideTmuxWindowForController:` (`PseudoTerminal.m:4220–4284`, a
clean model for our multi-action dialog). **Plan: add the window-projects
confirmation here** (return NO on Cancel), and make `windowWillClose(_:)` in the
model only do the *non-interactive* bookkeeping for the already-decided outcome
(or skip it entirely if `windowShouldClose:` already performed the archive/detach).
Watch the interaction: today both the running-jobs prompt and our prompt could
fire — coalesce so the user sees at most one dialog.

### 13b. Model API to call (sources/iTermWindowProjectsModel.swift)
| Outcome | Model call |
|---|---|
| Update & close (refresh snapshot, kill process) | `archiveWindow(t, to: p, andClose: true, keepJobsRunning: false)` (554–588) |
| Update & detach (refresh snapshot, keep process) | `archiveWindow(t, to: p, andClose: true, keepJobsRunning: true)` → parks via `parkSessionsForReattachment` (598–610) |
| Delete saved & close (remove archive, close) | `disassociateWindow(t)` (390–395) + remove the archived entry `removeWindow(_:from:)` (741–745) + close |
| Close only, leave stale snapshot | close without touching the existing archive (must suppress the auto-archive in `windowWillClose`) |
| Cancel | return NO from `windowShouldClose:` |

Other relevant: `associateWindow(_:with:)` (382), `project(for:)` (398),
`liveWindows(for:)` (405), `closeProject(_:keepJobsRunning:)` (423, the
"Detach/Archive All" batch path), `disassociateWindow` removes the
`liveAssociations[guid]` entry. Associations persist by `terminalGuid` in
`WindowProjectAssociations.json` (separate from `WindowProjects.json`);
`isTerminating` flag (model.swift ~166) makes `windowWillClose` no-op during quit
(set by `applicationWillTerminate`, ~492–500).

States today: **open/associated** (live, in `liveAssociations`), **detached**
(parked, process alive), **closed/archived** (snapshot only, process dead).
"Detach All"/"Archive All" route through `closeProject(keepJobsRunning:)`;
single-window context-menu/buttons route through `archiveWindow(...)` in
`iTermProjectsPanelController.swift` (archiveSelected 1452, detachSelected 1456,
disassociateSelected 1468, associateSelected 1386).

### 13c. Dialog mechanism: `iTermWarning` (sources/iTermWarning.h)
`iTermWarning` natively gives multi-button + a **“Remember my choice” checkbox +
per-selection persistence** — no custom accessory needed. This is the existing
idiom (see the tmux 4-button dialog above). Key selector:
```
+ (iTermWarningSelection)showWarningWithTitle:actions:actionMapping:accessory:
        identifier:silenceable:heading:cancelLabel:window:
```
- `actions:` up to 7 labels → `kiTermWarningSelection0…6`; there is also a
  `cancelLabel:` that is **never remembered** (perfect for Cancel).
- `silenceable: kiTermWarningTypePermanentlySilenceable` + an `identifier:`
  (convention `@"NoSync…"`) → auto-adds the “Remember my choice” checkbox and
  **persists the chosen selection** under that identifier in NSUserDefaults. So
  **iTermWarning IS the “config the don’t-ask-again saves to.”** Read it back with
  `+conditionalSavedSelectionForIdentifier:` / `+identifierIsSilenced:`; reset via
  `+clearSavedSelectionForIdentifier:` / the global `+toggleShowRememberedAlerts`.
- `actionMapping:` decouples button order from saved selection values — use it so
  we can reorder/insert buttons later without invalidating saved choices.
- `iTermWarningAction` supports `.destructive` (red button) and `.keyEquivalent`.

Trade-off vs a real `iTermPreferences` enum key: the NoSync identifier is
zero-extra-code and self-persisting, but it's **not surfaced in Settings UI**. If
we want a discoverable/resettable Settings control (DesignNotes §6c's "4-way
setting"), add a `kPreferenceKeyWindowProjectCloseBehavior` enum
(ask/update-close/update-detach/delete-close) to `iTermPreferences.h/.m`
(declare key, add to `+defaultValueMap`, read via `+integerForKey:`), and have the
dialog write to it when "don't ask again" is checked. Recommendation: start with
iTermWarning's built-in remember; promote to a Settings pref only if we want it in
the prefs window.

### 13d. App-quit analogue (§6d)
`iTermApplicationDelegate.applicationShouldTerminate:` (`iTermApplicationDelegate.m`
~918–1021) is the quit gate. Today it shows the standard "Quit iTerm2?" NSAlert
gated by `kPreferenceKeyPromptOnQuit` / `…EvenIfThereAreNoWindows`, with an
`iTermDisclosableView` "why am I being prompted" accessory. Window-projects quit
behavior is currently Option A: do nothing special, set `isTerminating`, preserve
associations, rely on native window restoration. The analogue dialog would either
(a) augment this single quit prompt with a project-aware choice
(Detach all / Update & close all / Just quit / Cancel), or (b) per-window apply the
same close-behavior setting. Counting associated open windows: iterate
`iTermController.sharedInstance().terminals()` and `model.project(for:)`.

### 13e. Other dialog facts
- Simple confirmations in the panel use plain `NSAlert` +
  `alert.buttons[0].hasDestructiveAction = true` (see
  `iTermProjectsPanelController.swift` delete-project ~661, restore-all ~684).
- Sheet vs app-modal: `NSAlert.runSheetModalForWindow:` for window-attached;
  `iTermWarning … window:self.window` presents as a sheet on that window.
